# ============================================================
# VS Code Desktop
# ============================================================

module "vscode-desktop" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/vscode-desktop/coder"
  version = "1.2.1"

  agent_id = coder_agent.main.id

  folder      = local.repo_dir
  open_recent = false
}

# ============================================================
# code-server
# ============================================================

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "1.5.0"

  agent_id = coder_agent.main.id

  folder    = local.repo_dir
  workspace = ""

  additional_args         = ""
  auto_install_extensions = false
  extensions_dir          = ""
  install_version         = ""
  offline                 = false

  open_in = "slim-window"
  port    = 13337

  use_cached            = false
  use_cached_extensions = false
}

# ============================================================
# Git Clone
#
# Repository:
#
# github.com
#      ↓
# secret/coder/github
#
# gitlab.com
#      ↓
# secret/coder/gitlab
# ============================================================

module "git-clone" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/git-clone/coder"
  version = "2.0.1"

  agent_id = coder_agent.main.id

  base_dir    = "/home/coder"
  folder_name = local.repo_name
  branch_name = data.coder_parameter.git_branch.value

  url = local.repo_url

  # ----------------------------------------------------------
  # Authentication
  # ----------------------------------------------------------

  pre_clone_script = <<-EOT
    set -euo pipefail

    echo "========================================"
    echo "Configuring Git"
    echo "========================================"

    git config --global user.name "OpenCode"
    git config --global user.email "opencode@coder.local"

    git config --global credential.helper store

    case "${local.repo_provider}" in

      github)

        echo "Configuring GitHub authentication..."

        cat > "$HOME/.git-credentials" <<'EOF'
https://x-access-token:${local.git_token}@github.com
EOF
        ;;

      gitlab)

        echo "Configuring GitLab authentication..."

        cat > "$HOME/.git-credentials" <<'EOF'
https://oauth2:${local.git_token}@gitlab.com
EOF
        ;;

      *)

        echo "ERROR: Unsupported Git provider."
        echo
        echo "Repository:"
        echo "  ${local.repo_url}"
        echo
        echo "Detected host:"
        echo "  ${local.repo_host}"
        echo
        echo "Supported:"
        echo "  github.com"
        echo "  gitlab.com"

        exit 1
        ;;

    esac

    chmod 600 "$HOME/.git-credentials"

    echo "Git credentials configured."
  EOT

  # ----------------------------------------------------------
  # Post Clone
  # ----------------------------------------------------------

  post_clone_script = <<-EOT
    set -euo pipefail

    cd "${local.repo_dir}"

    # Ensure credentials are never embedded in origin.
    git remote set-url origin "${local.repo_url}"

    echo "Fetching latest remote state..."

    git fetch --all --prune

    DEFAULT_BRANCH="$(
      git remote show origin |
      sed -n '/HEAD branch/s/.*: //p'
    )"

    if [ -n "$DEFAULT_BRANCH" ]; then
      git config --local coder.defaultBranch "$DEFAULT_BRANCH"
    fi

    echo
    echo "========================================"
    echo "Repository ready"
    echo "========================================"
    echo "Provider       : ${local.repo_provider}"
    echo "Host           : ${local.repo_host}"
    echo "Repository     : ${local.repo_name}"
    echo "Directory      : ${local.repo_dir}"
    echo "Origin         : ${local.repo_url}"
    echo "Default branch : $${DEFAULT_BRANCH:-unknown}"
    echo "========================================"
  EOT
}

# ============================================================
# OpenCode
# ============================================================

module "opencode" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder-labs/opencode/coder"
  version = "0.1.2"

  agent_id = coder_agent.main.id

  # ----------------------------------------------------------
  # Repository working directory
  # ----------------------------------------------------------

  workdir = local.repo_dir

  # ----------------------------------------------------------
  # Wait for Git Clone
  #
  # OpenCode performs:
  #
  # cd "$ARG_WORKDIR"
  #
  # so .git must exist first.
  # ----------------------------------------------------------

  pre_install_script = <<-EOT
    set -euo pipefail

    echo "Waiting for repository clone..."

    for i in $(seq 1 120); do

      if [ -d "${local.repo_dir}/.git" ]; then
        echo "Repository ready at ${local.repo_dir}"
        exit 0
      fi

      echo "Repository not ready yet... ($i/120)"
      sleep 2

    done

    echo "ERROR: Repository was not cloned within 240 seconds."
    exit 1
  EOT

  # ----------------------------------------------------------
  # User Task
  # ----------------------------------------------------------

  ai_prompt = data.coder_parameter.opencode_task.value

  # ----------------------------------------------------------
  # OpenCode Authentication
  #
  # Pulled from:
  #
  # secret/coder/opencode
  #
  # auth_json = contents of:
  #
  # ~/.local/share/opencode/auth.json
  # ----------------------------------------------------------

  auth_json = local.opencode_auth_json

  # ----------------------------------------------------------
  # OpenCode Configuration
  # ----------------------------------------------------------

  config_json = jsonencode({
    "$schema" = "https://opencode.ai/config.json"

    model = "openai/gpt-5.6-luna"
  })

  # ----------------------------------------------------------
  # Coder Integration
  # ----------------------------------------------------------

  report_tasks = true
  cli_app      = true

  web_app_display_name = "OpenCode"
  cli_app_display_name = "OpenCode CLI"

  # ----------------------------------------------------------
  # Installation
  # ----------------------------------------------------------

  install_opencode = true
  opencode_version = "latest"

  # ----------------------------------------------------------
  # Session
  # ----------------------------------------------------------

  continue   = false
  session_id = ""

  depends_on = [
    module.git-clone
  ]
}
