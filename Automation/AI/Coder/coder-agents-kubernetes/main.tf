terraform {
  required_version = ">= 1.10"

  required_providers {
    coder = {
      source = "coder/coder"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}

# ============================================================
# Coder Data Sources
# ============================================================

data "coder_provisioner" "me" {}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

# ============================================================
# User Parameters
# ============================================================

data "coder_parameter" "git_repo_url" {
  name         = "git_repo_url"
  display_name = "Git Repository"

  description = <<-EOT
    HTTPS URL of a GitHub or GitLab repository.

    Examples:

    https://github.com/codesenju/iy-studios.git

    https://gitlab.com/group/project.git
  EOT

  type    = "string"
  mutable = true

  default = "https://github.com/codesenju/iy-studios.git"
}

data "coder_parameter" "git_branch" {
  name         = "git_branch"
  display_name = "Git Branch"
  description  = "Branch to clone. Defaults to main."
  type         = "string"
  mutable      = true
  default      = "main"
}

data "coder_parameter" "app_ports" {
  name         = "app_ports"
  display_name = "Docker App Ports"
  description  = "Comma-separated TCP ports published by Docker Compose, for example 5432,9001,3000,8080,8000."
  type         = "string"
  mutable      = true
  default      = "8080"
}

# ============================================================
# Configuration
# ============================================================

variable "openbao_address" {
  type        = string
  description = "Primary OpenBao address"

  default = "https://openbao.local.domain.com"
}

variable "workspace_namespace" {
  type        = string
  description = "Namespace where Coder workspace pods run"

  default = "coder"
}

variable "workspace_storage_class" {
  type        = string
  description = "StorageClass for workspace persistent storage"

  default = "nfs-csi"
}

variable "workspace_storage_size" {
  type        = string
  description = "Persistent workspace home directory size"

  default = "20Gi"
}

variable "workspace_image" {
  type        = string
  description = "Container image used for workspace pods"

  default = "codercom/enterprise-base:ubuntu"
}

# ============================================================
# Kubernetes Provider
#
# Coder is running inside the same Kubernetes cluster.
# ============================================================

provider "kubernetes" {
  host = "https://kubernetes.default.svc"

  token = file(
    "/var/run/secrets/kubernetes.io/serviceaccount/token"
  )

  cluster_ca_certificate = file(
    "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  )
}

# ============================================================
# OpenBao Provider
#
# Authentication:
#
# Coder ServiceAccount JWT
#       ↓
# auth/kubernetes/login
#       ↓
# OpenBao role: coder
#       ↓
# policy: coder-opencode
# ============================================================

provider "vault" {
  address = var.openbao_address

  # Use the short-lived token returned from Kubernetes auth
  # directly. Do not ask OpenBao to create another child token.
  skip_child_token = true

  auth_login {
    path = "auth/kubernetes/login"

    parameters = {
      role = "coder"

      jwt = file(
        "/var/run/secrets/kubernetes.io/serviceaccount/token"
      )
    }
  }
}

# ============================================================
# Repository Derived Values
# ============================================================

locals {
  repo_url = trimsuffix(
    trimspace(data.coder_parameter.git_repo_url.value),
    "/"
  )

  # Example:
  #
  # https://github.com/codesenju/iy-studios.git
  #
  # -> github.com
  repo_host = regex(
    "^https?://([^/]+)/",
    local.repo_url
  )[0]

  # iy-studios.git -> iy-studios
  repo_name = trimsuffix(
    basename(local.repo_url),
    ".git"
  )

  # /home/coder/iy-studios
  repo_dir = "/home/coder/${local.repo_name}"

  # Detect Git provider
  repo_provider = (
    local.repo_host == "github.com"
    ? "github"
    : local.repo_host == "gitlab.com"
    ? "gitlab"
    : "unsupported"
  )

  # Kubernetes resource name
  workspace_name = substr(
    lower(
      "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    ),
    0,
    63
  )
}

# ============================================================
# OpenBao Secrets
#
# secret/coder/github
#   token
#
# secret/coder/gitlab
#   token
#
# Only the selected Git provider token is read.
# ============================================================

data "vault_kv_secret_v2" "github" {
  count = local.repo_provider == "github" ? 1 : 0

  mount = "secret"
  name  = "coder/github"
}

data "vault_kv_secret_v2" "gitlab" {
  count = local.repo_provider == "gitlab" ? 1 : 0

  mount = "secret"
  name  = "coder/gitlab"
}

locals {
  git_token = (
    local.repo_provider == "github"
    ? data.vault_kv_secret_v2.github[0].data["token"]
    : local.repo_provider == "gitlab"
    ? data.vault_kv_secret_v2.gitlab[0].data["token"]
    : ""
  )
}

# ============================================================
# Coder Agent
#
# NOTE:
# coder_agent.dir intentionally NOT used because it is
# deprecated in current Coder provider releases.
# ============================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

resource "coder_app" "docker_app" {
  for_each = toset([
    for port in split(",", data.coder_parameter.app_ports.value) :
    trimspace(port)
    if trimspace(port) != ""
  ])

  agent_id     = coder_agent.main.id
  slug         = "docker-${each.key}"
  display_name = "Docker App (${each.key})"
  icon         = "/icon/desktop.svg"
  url          = "http://127.0.0.1:${each.key}"
  share        = "owner"

  healthcheck {
    url       = "http://127.0.0.1:${each.key}"
    interval  = 10
    threshold = 3
  }
}

# ============================================================
# Persistent Workspace Storage
#
# This PVC is NOT tied to workspace start_count so it survives
# workspace stop/start cycles.
# ============================================================

resource "kubernetes_persistent_volume_claim_v1" "workspace_home" {
  metadata {
    name      = "${local.workspace_name}-home"
    namespace = var.workspace_namespace

    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = local.workspace_name

      "com.coder.workspace.name"  = data.coder_workspace.me.name
      "com.coder.workspace.owner" = data.coder_workspace_owner.me.name
    }
  }

  spec {
    access_modes = [
      "ReadWriteOnce"
    ]

    storage_class_name = var.workspace_storage_class

    resources {
      requests = {
        storage = var.workspace_storage_size
      }
    }
  }
}

# ============================================================
# Workspace Pod
#
# This is the actual runtime that executes the Coder agent.
# ============================================================

resource "kubernetes_pod_v1" "workspace" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = local.workspace_name
    namespace = var.workspace_namespace

    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = local.workspace_name

      "com.coder.workspace.name"  = data.coder_workspace.me.name
      "com.coder.workspace.owner" = data.coder_workspace_owner.me.name
    }
  }

  spec {
    restart_policy = "Always"

    security_context {
      run_as_non_root = true
      run_as_user     = 1000
      run_as_group    = 1000
      fs_group        = 1000
    }

    init_container {
      name    = "install-docker-client"
      image   = "docker:29-dind"
      command = ["sh", "-c", "cp /usr/local/bin/docker /docker-bin/docker"]

      volume_mount {
        name       = "docker-bin"
        mount_path = "/docker-bin"
      }
    }

    container {
      name = "workspace"

      image             = var.workspace_image
      image_pull_policy = "IfNotPresent"

      command = [
        "sh",
        "-c",
        <<-EOT
          set -eu

          if ! command -v opencode >/dev/null 2>&1 && [ ! -x "$HOME/.opencode/bin/opencode" ]; then
            curl -fsSL https://opencode.ai/install | bash
          fi

          export PATH="$HOME/.opencode/bin:$PATH"
          command -v opencode >/dev/null 2>&1

          exec sh -c "$1"
        EOT
        ,
        "coder-agent-init",
        coder_agent.main.init_script
      ]

      working_dir = "/home/coder"

      security_context {
        run_as_user     = 1000
        run_as_group    = 1000
        run_as_non_root = true
      }

      # ------------------------------------------------------
      # Coder Agent
      # ------------------------------------------------------

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      env {
        name  = "HOME"
        value = "/home/coder"
      }

      env {
        name  = "DOCKER_HOST"
        value = "tcp://127.0.0.1:2375"
      }

      # ------------------------------------------------------
      # Repository Information
      # ------------------------------------------------------

      env {
        name  = "REPOSITORY_URL"
        value = local.repo_url
      }

      env {
        name  = "REPOSITORY_NAME"
        value = local.repo_name
      }

      env {
        name  = "REPOSITORY_DIR"
        value = local.repo_dir
      }

      env {
        name  = "REPOSITORY_PROVIDER"
        value = local.repo_provider
      }

      # ------------------------------------------------------
      # Resources
      # ------------------------------------------------------

      resources {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }

        limits = {
          cpu    = "4"
          memory = "8Gi"
        }
      }

      # ------------------------------------------------------
      # Persistent HOME
      # ------------------------------------------------------

      volume_mount {
        name       = "home"
        mount_path = "/home/coder"
        read_only  = false
      }

      volume_mount {
        name       = "docker-bin"
        mount_path = "/usr/local/bin/docker"
        sub_path   = "docker"
        read_only  = true
      }
    }

    container {
      name  = "dind"
      image = "docker:29-dind"

      args = [
        "--host=tcp://0.0.0.0:2375",
        "--host=unix:///var/run/docker.sock",
        "--tls=false",
      ]

      security_context {
        privileged                 = true
        run_as_user                = 0
        run_as_group               = 0
        run_as_non_root            = false
        allow_privilege_escalation = true
      }

      env {
        name  = "DOCKER_TLS_CERTDIR"
        value = ""
      }

      volume_mount {
        name       = "docker-graph-storage"
        mount_path = "/var/lib/docker"
      }
    }

    volume {
      name = "home"

      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.workspace_home.metadata[0].name
        read_only  = false
      }
    }

    volume {
      name = "docker-bin"

      empty_dir {}
    }

    volume {
      name = "docker-graph-storage"

      empty_dir {}
    }
  }

  depends_on = [
    kubernetes_persistent_volume_claim_v1.workspace_home
  ]
}

# ============================================================
# Coder Workspace Metadata
# ============================================================

resource "coder_metadata" "workspace" {
  count = data.coder_workspace.me.start_count

  resource_id = kubernetes_pod_v1.workspace[0].id

  item {
    key   = "pod"
    value = kubernetes_pod_v1.workspace[0].metadata[0].name
  }

  item {
    key   = "namespace"
    value = var.workspace_namespace
  }

  item {
    key   = "repository"
    value = local.repo_name
  }

  item {
    key   = "provider"
    value = local.repo_provider
  }

  item {
    key   = "storage"
    value = var.workspace_storage_size
  }
}

# ============================================================
# Workspace Environment
# ============================================================

resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "WELCOME_MESSAGE"

  value = "Welcome to your OpenCode workspace!"
}

resource "coder_env" "repository_url" {
  agent_id = coder_agent.main.id
  name     = "REPOSITORY_URL"

  value = local.repo_url
}

resource "coder_env" "repository_name" {
  agent_id = coder_agent.main.id
  name     = "REPOSITORY_NAME"

  value = local.repo_name
}

resource "coder_env" "repository_dir" {
  agent_id = coder_agent.main.id
  name     = "REPOSITORY_DIR"

  value = local.repo_dir
}

resource "coder_env" "repository_provider" {
  agent_id = coder_agent.main.id
  name     = "REPOSITORY_PROVIDER"

  value = local.repo_provider
}
