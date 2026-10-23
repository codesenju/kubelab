# Coder Kubernetes Templates

This directory contains three templates:

- `scratch/`: existing OpenCode + AgentAPI workspace template.
- `scratch-designer/`: OpenCode workspace with designer skills and Playwright MCP.
- `coder-agents-kubernetes/`: modern Coder Agents workspace template.

All templates include Docker-in-Docker (DIND): a privileged `docker:29-dind`
sidecar, Docker CLI installed by an init container, and `DOCKER_HOST` set to
`tcp://127.0.0.1:2375` in the workspace container.

All templates expose a mutable `app_ports` parameter. Set comma-separated TCP
ports, and Coder creates one proxied app link per port.

## Table of Contents

- [DIND Security](#dind-security)
- [Install And Configure Coder CLI](#install-and-configure-coder-cli)
- [Prerequisites](#prerequisites)
- [Validate A Local Template Folder](#validate-a-local-template-folder)
- [Push Existing OpenCode Template](#push-existing-opencode-template)
- [Push Modern Template](#push-modern-template)
- [Create Workspace From Published Template](#create-workspace-from-published-template)
- [Publish DIND Changes](#publish-dind-changes)
- [Create Test Workspace](#create-test-workspace)
- [Validate Test Workspace](#validate-test-workspace)
- [Rollback](#rollback)
- [Important Differences](#important-differences)

## DIND Security

DIND requires one privileged container per workspace. This allows Docker builds
inside the workspace and increases isolation risk. Docker graph storage uses
`emptyDir`, so images and containers disappear when the workspace pod is
recreated. Do not expose port `2375` outside the pod.

Existing workspaces remain unchanged when templates are updated. Test template changes in a new workspace first.

## Install And Configure Coder CLI

macOS with Homebrew:

```bash
brew install coder
coder version
```

Linux:

```bash
curl -fsSL https://coder.com/install.sh | sh
coder version
```

Log in interactively. This opens the browser for authentication:

```bash
coder login https://coder.local.domain.com
```

Confirm the active server and identity:

```bash
coder whoami
coder templates list
```

For automation, create a Coder API token in the Coder UI, then use:

```bash
export CODER_URL="https://coder.local.domain.com"
export CODER_SESSION_TOKEN="REPLACE_WITH_CODER_API_TOKEN"
coder whoami
```

Do not commit `CODER_SESSION_TOKEN` or place it in template files.

## Prerequisites

```bash
coder login https://coder.local.domain.com
kubectl config current-context
kubectl -n coder get pods
```

Verify Coder Agents has an enabled LLM provider and model in Coder Admin settings before creating a workspace.

OpenBao must already contain Git credentials:

```text
secret/coder/github: token
secret/coder/gitlab: token
```

The Coder ServiceAccount must be allowed to authenticate to OpenBao role `coder`.

## Validate A Local Template Folder

Coder creates templates from folders by publishing them to the Coder server.
There is no direct `coder create` operation from a local Terraform folder.

```bash
cd ~/codesenju/repos/kubelab/Automation/AI/Coder/coder-agents-kubernetes
pwd
ls -lah
```

Expected files:

```text
README.md
main.tf
modules.tf
```

## Push Existing OpenCode Template

Use this only to restore or update existing `scratch` template.

```bash
cd ~/codesenju/repos/kubelab/Automation/AI/Coder/scratch
coder templates push scratch \
  --directory . \
  --message "Update scratch template" \
  --yes
```

Equivalent absolute-path command:

```bash
coder templates push scratch \
  --directory ~/codesenju/repos/kubelab/Automation/AI/Coder/scratch \
  --message "Update scratch template" \
  --yes
```

Do not change `iystudios` unless intending to rebuild it.

## Push Modern Template

```bash
cd ~/codesenju/repos/kubelab/Automation/AI/Coder/coder-agents-kubernetes
coder templates push coder-agents-kubernetes \
  --directory . \
  --message "Update Coder Agents Kubernetes template" \
  --yes
```

Equivalent absolute-path command:

```bash
coder templates push coder-agents-kubernetes \
  --directory ~/codesenju/repos/kubelab/Automation/AI/Coder/coder-agents-kubernetes \
  --message "Update Coder Agents Kubernetes template" \
  --yes
```

Confirm template status:

```bash
coder templates list
coder templates versions list coder-agents-kubernetes
```

## Create Workspace From Published Template

Push local files first, then create a workspace from the published template:

```bash
coder create coder-agents-test \
  --template coder-agents-kubernetes \
  --parameter git_repo_url=https://gitlab.com/iysynergy/iystudios.git
```

List and start it:

```bash
coder list
coder start coder-agents-test
```

Open workspace in browser:

```bash
coder open coder-agents-test
```

Create OpenCode workspace instead:

```bash
coder create opencode-test \
  --template scratch \
  --parameter git_repo_url=https://gitlab.com/iysynergy/iystudios.git
```

Set multiple ports when creating or updating a workspace. Use a YAML parameter
file because Coder CLI treats unescaped commas in `--parameter` values as
separate arguments:

```yaml
# workspace-parameters.yaml
app_ports: "5432,9001,3000,8080,8000"
```

```bash
coder update iystudios \
  --rich-parameter-file workspace-parameters.yaml
```

Each port appears as a separate Coder app, for example `Docker App (8080)`.
Docker Compose must publish matching ports and services must listen on
`0.0.0.0`, not only `127.0.0.1`:

```yaml
services:
  web:
    ports:
      - "8080:8080"
```

## Publish DIND Changes

Publish each template separately after changing its files:

```bash
cd ~/codesenju/repos/kubelab/Automation/AI/Coder/scratch
coder templates push scratch --directory . --message "Add Docker-in-Docker" --yes

cd ~/codesenju/repos/kubelab/Automation/AI/Coder/coder-agents-kubernetes
coder templates push coder-agents-kubernetes --directory . --message "Add Docker-in-Docker" --yes
```

## Create Test Workspace

```bash
coder create coder-agents-test \
  --template coder-agents-kubernetes \
  --parameter git_repo_url=https://gitlab.com/iysynergy/iystudios.git
```

Check workspace status:

```bash
coder list
kubectl -n coder get pods -o wide
kubectl -n coder get pvc
```

Expected pod security context:

```bash
kubectl -n coder get pod coder-jazziro-coder-agents-test \
  -o jsonpath='{.spec.containers[0].securityContext}{"\n"}'
```

The modern template installs OpenCode CLI at workspace startup but does not run OpenCode or AgentAPI automatically and does not require privilege escalation.

## Validate Test Workspace

```bash
kubectl -n coder exec coder-jazziro-coder-agents-test -- id
kubectl -n coder exec coder-jazziro-coder-agents-test -- sh -lc \
  'grep -i NoNewPrivs /proc/1/status; git -C /home/coder/iystudios status --short --branch; git -C /home/coder/iystudios remote -v'

kubectl -n coder exec coder-jazziro-coder-agents-test -- sh -lc \
  'docker version && docker run --rm hello-world'
```

Use Coder Agents chat and select `coder-agents-test`. Validate:

```text
Inspect /home/coder/iystudios without changing files. Report repository status, default branch, and current commit.
```

Then validate branch safety:

```text
Create branch fix/coder-agents-smoke-test. Add a harmless documentation change, run relevant validation, review the diff, commit it, and push only this branch. Never modify or merge into main. Never force-push.
```

Verify branch on GitLab before any merge:

```bash
git -C /home/coder/iystudios fetch --all --prune
```

## Rollback

Stop and delete test workspace only:

```bash
coder stop coder-agents-test
coder delete coder-agents-test --yes
```

Existing OpenCode workspace remains available:

```bash
coder list
coder start iystudios
```

## Important Differences

`scratch`:

- Installs OpenCode.
- Uses deprecated AgentAPI integration.
- Requires `secret/coder/opencode`.
- Requires `allow_privilege_escalation=true` for AgentAPI installation.

`coder-agents-kubernetes`:

- Installs OpenCode CLI at workspace startup.
- Uses Coder's control-plane agent.
- Requires no OpenCode or AgentAPI process.
- Requires no OpenCode `auth.json`.
- Preserves GitLab/GitHub OpenBao authentication.
- Keeps workspace privilege escalation disabled.

All templates:

- Run Docker daemon as privileged `docker:29-dind` sidecar.
- Install Docker CLI into workspace from an init container.
- Set `DOCKER_HOST=tcp://127.0.0.1:2375`.
