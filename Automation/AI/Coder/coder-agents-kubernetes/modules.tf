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

    git config --global user.name "Coder Agent"
    git config --global user.email "coder-agent@coder.local"

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
