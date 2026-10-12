# OpenBao Secret Management

Set OpenBao endpoint before using CLI commands:

```bash
export BAO_ADDR="https://openbao.example.com:8200"
bao login
```

Replace `secret` with your KV mount if different.

## Method 1: Store `.env` As Raw File

Stores complete `.env` contents as one KV value named `env_file`:

```bash
bao kv put secret/coder/env_files/iystudios \
  env_file=@.env
```

Retrieve raw file:

```bash
bao kv get -field=env_file \
  secret/coder/env_files/iystudios > .env

## Upload `.env` Variables As Individual Keys

For simple `KEY=value` files, excluding comments and blank lines:

```bash
bao kv put secret/coder/env_files/iystudios \
  $(grep -Ev '^\s*(#|$)' .env)
```

Values containing spaces, shell expansion, or multiline content should use the
raw-file method above or JSON instead.
```

## Method 2: Store Variables As Individual Keys

Use JSON when creating the secret in OpenBao UI or CLI:

```json
{
  "DATABASE_URL": "postgres://user:password@db/app",
  "API_KEY": "replace-me",
  "NODE_ENV": "production"
}
```

Upload JSON:

```bash
bao kv put secret/coder/env_files/iystudios @secrets.json
```

Or upload explicit values:

```bash
bao kv put secret/coder/env_files/iystudios \
  DATABASE_URL="postgres://user:password@db/app" \
  API_KEY="replace-me" \
  NODE_ENV="production"
```

## Patch Existing Secret

Use `bao kv patch` when updating one field. It preserves other fields at the
secret path. Do not use `bao kv put` unless replacing the complete secret.

Update OpenCode OAuth credentials without printing them:

```bash
bao kv patch secret/coder/opencode \
  auth_json="$(< "$HOME/.local/share/opencode/auth.json")"
```

Confirm the field exists without displaying its value:

```bash
bao kv get -field=auth_json secret/coder/opencode >/dev/null \
  && echo "auth_json updated"
```

The `auth_json` file contains sensitive credentials. Never commit it, paste it
into chat, or include it in logs.

Retrieve all keys:

```bash
bao kv get secret/coder/env_files/iystudios
```

Retrieve one key:

```bash
bao kv get -field=API_KEY secret/coder/env_files/iystudios
```

Export individual keys as `.env`-style output:

```bash
bao kv get -format=json secret/coder/env_files/iystudios \
  | jq -r '.data.data | to_entries[] | "\(.key)=\(.value|@json)"' > .env
```

## Verify Path

```bash
bao kv metadata get secret/coder/env_files/iystudios
```

Do not commit `.env`, `secrets.json`, or retrieved secret files.

## Repository Setup

These repository components provide the OpenBao deployment and Coder access path.

### `addons/openbao-transit.yaml`

Ansible creates the transit OpenBao configuration and an Argo CD application. The
application deploys `kustomize/openbao-transit/overlays/prod` into namespace
`zero-trust`, then exposes it through `openbao-transit.<local_dns>`.

### `kustomize/openbao-transit`

Deploys one OpenBao Transit instance with Raft storage on the NAS path
`/mnt/pool2/AppData/openbao-transit`. The service listens internally on port
`8200`. This instance supplies the `transit/` seal backend used to auto-unseal
the primary OpenBao cluster.

### `addons/openbao.yaml`

Creates the Kubernetes Secret `openbao-transit-seal`, containing the transit
token, and deploys the primary OpenBao Helm release. The primary cluster uses
three Raft replicas with persistent storage. Its transit seal points to
`openbao-transit.<local_dns>` and key `openbao-unseal`. The primary UI/API is
exposed at `openbao.<local_dns>`.

### `addons/openbao-coder.yaml`

Creates OpenBao Kubernetes TokenReview RBAC, enables KV v2 at mount `secret`,
stores GitHub and GitLab tokens, and creates policy `coder-opencode`.

The policy grants read access to:

```text
secret/data/coder/opencode
secret/data/coder/github
secret/data/coder/gitlab
```

It binds policy access to Kubernetes ServiceAccount `coder` in namespace
`coder` through OpenBao Kubernetes auth role `coder`, with a one-hour token TTL.

### `Automation/AI/Coder`

The Coder Terraform template uses the workspace pod's ServiceAccount JWT to
authenticate at `auth/kubernetes/login` as role `coder`. The Vault provider is
configured for the primary OpenBao address and reads only the selected Git
provider secret:

```text
GitHub repository -> secret/coder/github -> token
GitLab repository  -> secret/coder/gitlab  -> token
```

The selected token is used by the Coder workspace template for repository
access. The workspace does not receive the other provider's token. The policy
also permits `secret/coder/opencode`; that path must be populated separately if
OpenCode credentials are needed by a workspace.

Secret flow:

```text
Coder workspace ServiceAccount JWT
  -> OpenBao Kubernetes auth role: coder
  -> policy: coder-opencode
  -> secret/coder/github or secret/coder/gitlab
  -> Terraform provider -> workspace configuration
```

OpenBao stores secret values; Transit OpenBao protects the primary cluster's
unseal process. Transit does not automatically expose KV secrets to Coder.
