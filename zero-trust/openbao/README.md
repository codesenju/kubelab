# OpenBao Secret Management

Set the OpenBao endpoint before using CLI commands:

```bash
export BAO_ADDR="https://openbao.local.example.com"
bao login
```

Replace `secret` with your KV mount if different.

The root token is for bootstrap and recovery only. For daily administration and
application access, create named tokens with limited policies. See
[Access Tokens](#access-tokens).

## Table of Contents

- [Quick Start](#quick-start)
- [Secret Operations](#secret-operations)
  - [Store `.env` as a raw file](#store-env-as-a-raw-file)
  - [Store `.env` variables as individual keys](#store-env-variables-as-individual-keys)
  - [Store variables as individual keys](#store-variables-as-individual-keys)
  - [Patch an existing secret](#patch-an-existing-secret)
  - [Retrieve secrets](#retrieve-secrets)
  - [Verify a path](#verify-a-path)
- [Access Tokens](#access-tokens)
  - [Admin token](#admin-token)
    - [Create or rotate](#create-or-rotate)
    - [Use the token](#use-the-token)
    - [Verify admin capabilities](#verify-admin-capabilities)
    - [Create OIDC admin login](#create-oidc-admin-login)
    - [Retire the root token](#retire-the-root-token)
  - [Read-only token](#read-only-token)
- [OIDC](#oidc)
  - [OIDC admin role](#oidc-admin-role)
- [Repository Setup](#repository-setup)
  - [Transit addon](#transit-addon)
  - [Transit kustomize overlay](#transit-kustomize-overlay)
  - [Primary OpenBao addon](#primary-openbao-addon)
  - [Coder integration addon](#coder-integration-addon)
  - [Coder workspace template](#coder-workspace-template)
- [Recovery: Transit-Sealed Primary](#recovery-transit-sealed-primary)
  - [What happened](#what-happened)
  - [Recovery commands](#recovery-commands)
  - [Important safety rules](#important-safety-rules)

## Quick Start

Authenticate with the root token only for bootstrap, or with a named token or
OIDC role for normal work:

```bash
export BAO_ADDR="https://openbao.local.example.com"

# Existing named token
export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"

# Or interactive OIDC login
bao login -method=oidc
```

Check the session:

```bash
bao token lookup
```

## Secret Operations

These are the common daily operations. Replace `secret` with your KV mount if
different.

### Store `.env` as a raw file

Stores complete `.env` contents as one KV value named `env_file`:

```bash
bao kv put secret/coder/env_files/iystudios \
  env_file=@.env
```

### Store `.env` variables as individual keys

For simple `KEY=value` files, excluding comments and blank lines:

```bash
bao kv put secret/coder/env_files/iystudios \
  $(grep -Ev '^\s*(#|$)' .env)
```

Values containing spaces, shell expansion, or multiline content should use the
raw-file method above or JSON instead.

### Store variables as individual keys

Use JSON when creating the secret in the OpenBao UI or CLI:

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

### Patch an existing secret

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

### Retrieve secrets

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

Retrieve a raw file:

```bash
bao kv get -field=env_file \
  secret/coder/env_files/iystudios > .env
```

### Verify a path

```bash
bao kv metadata get secret/coder/env_files/iystudios
```

Do not commit `.env`, `secrets.json`, or retrieved secret files.

## Access Tokens

The root token is break-glass only. Use named, revocable tokens with explicit
policies.

Policy and helper files:

```text
zero-trust/openbao/policies/platform-admin.hcl
zero-trust/openbao/policies/secrets-readonly.hcl
zero-trust/openbao/setup-platform-admin.sh
```

### Admin token

`platform-admin` is a root-equivalent policy attached to a named, periodic,
revocable token. Use it for day-to-day administration: policies, auth methods
(including OIDC), secrets engines, identities, leases, and audit devices.

The token is not the root token. It can be revoked or rotated without
re-initializing OpenBao.

#### Create or rotate

Requires the root token once. The command prompts without echoing, and the root
token is not written to disk.

```bash
export BAO_ADDR="https://openbao.local.example.com"

read -rsp "Root token: " BAO_TOKEN; echo; export BAO_TOKEN
bash zero-trust/openbao/setup-platform-admin.sh
unset BAO_TOKEN
```

Token is stored at `~/.config/openbao/platform-admin.token` with mode `600`.
Rerunning the script revokes the previous generated token first, then creates a
replacement.

#### Use the token

```bash
export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"
bao token lookup
```

Do not commit the token file. To stop using it in the current shell:

```bash
unset BAO_TOKEN
```

#### Verify admin capabilities

```bash
export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"

bao policy list
bao auth list
bao secrets list
bao token capabilities sys/policies/acl/platform-admin
```

Expected capability output includes `sudo`, `create`, `read`, `update`,
`delete`, and `list`.

#### Create OIDC admin login

Use the same `platform-admin` policy with an OIDC role. See
[OIDC admin role](#oidc-admin-role).

#### Retire the root token

Only do this after the new token has been verified. Revoking the root token is
reversible only by generating a new root token with the recovery keys
(threshold 3 of 5).

```bash
export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"

read -rsp "Root token to revoke: " ROOT_TOKEN; echo
bao token revoke "$ROOT_TOKEN"
unset ROOT_TOKEN
```

Keep the recovery keys offline. They are the break-glass path if the admin
token is lost or revoked.

### Read-only token

Read and list access to every path. Create it with the admin token:

```bash
export BAO_ADDR="https://openbao.local.example.com"
export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"

cd /Users/jazziro/codesenju/repos/kubelab
bao policy write secrets-readonly \
  zero-trust/openbao/policies/secrets-readonly.hcl

READONLY_TOKEN="$(bao token create \
  -policy=secrets-readonly \
  -display-name=secrets-readonly \
  -orphan \
  -period=768h \
  -ttl=768h \
  -format=json | jq -r '.auth.client_token // empty')"

test -n "$READONLY_TOKEN" || { echo "token creation failed" >&2; exit 1; }

mkdir -p ~/.config/openbao
(umask 077; printf '%s' "$READONLY_TOKEN" > ~/.config/openbao/secrets-readonly.token)
chmod 600 ~/.config/openbao/secrets-readonly.token
unset READONLY_TOKEN

# verify
export BAO_TOKEN="$(cat ~/.config/openbao/secrets-readonly.token)"
bao kv list secret/
bao token capabilities secret/data/coder/github
bao token capabilities sys/policies/acl
```

Expected capabilities: `read`, `list`. Writes return `403`.

The policy is `path "*"` with `read` and `list`. It can read any secret path and
list metadata, including readable `sys/` endpoints, but it has no `create`,
`update`, `delete`, or `sudo` capability. Sudo-only operations such as
seal/unseal, raw storage, and policy writes remain blocked.

Rotate the read-only token with the admin token:

```bash
export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"
bao token revoke "$(cat ~/.config/openbao/secrets-readonly.token)"
rm -f ~/.config/openbao/secrets-readonly.token
```

Then rerun the `bao token create` block above.

## OIDC

Enable OIDC:

```bash
bao auth enable oidc
```

Create the read-only `reader` policy:

```bash
bao policy write reader - <<'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata" {
  capabilities = ["list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

path "sys/internal/ui/mounts" {
  capabilities = ["read"]
}

path "sys/internal/ui/mounts/*" {
  capabilities = ["read"]
}
EOF
```

Configure OIDC. Replace placeholders with values from your identity provider:

```bash
bao write auth/oidc/config \
  oidc_discovery_url="https://auth.<domain>/application/o/open-bao/" \
  oidc_client_id="<oidc_client_id>" \
  oidc_client_secret="<oidc_client_secret>" \
  default_role="reader"
```

Create the reader role:

```bash
bao write auth/oidc/role/reader \
  bound_audiences="<oidc_client_id>" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  allowed_redirect_uris="https://openbao.local.example.com/ui/vault/auth/oidc/oidc/callback" \
  user_claim="sub" \
  token_policies="reader"
```

### OIDC admin role

Optional. Bind `platform-admin` to an identity-provider group:

```bash
bao write auth/oidc/role/platform-admin \
  bound_audiences="<oidc_client_id>" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  allowed_redirect_uris="https://openbao.local.example.com/ui/vault/auth/oidc/oidc/callback" \
  user_claim="sub" \
  groups_claim="groups" \
  bound_claims='{"groups":["openbao-admins"]}' \
  token_policies="platform-admin" \
  token_ttl=1h \
  token_max_ttl=8h
```

If the identity provider does not expose groups, bind to a subject instead:

```bash
bao write auth/oidc/role/platform-admin \
  bound_audiences="<oidc_client_id>" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  allowed_redirect_uris="https://openbao.local.example.com/ui/vault/auth/oidc/oidc/callback" \
  user_claim="sub" \
  bound_claims='{"sub":["<oidc-subject>"]}' \
  token_policies="platform-admin" \
  token_ttl=1h \
  token_max_ttl=8h
```

Because `default_role` is `reader`, select the admin role explicitly at login:

```bash
bao login -method=oidc role=platform-admin
```

## Repository Setup

These repository components provide the OpenBao deployment and Coder access path.

### Transit addon

`addons/openbao-transit.yaml`

Ansible creates the transit OpenBao configuration and an Argo CD application. The
application deploys `kustomize/openbao-transit/overlays/prod` into namespace
`zero-trust`, then exposes it through `openbao-transit.<local_dns>`.

### Transit kustomize overlay

`kustomize/openbao-transit`

Deploys one OpenBao Transit instance with Raft storage on the NAS path
`/mnt/pool2/AppData/openbao-transit`. The service listens internally on port
`8200`. This instance supplies the `transit/` seal backend used to auto-unseal
the primary OpenBao cluster.

### Primary OpenBao addon

`addons/openbao.yaml`

Creates the Kubernetes Secret `openbao-transit-seal`, containing the transit
token, and deploys the primary OpenBao Helm release. The primary cluster uses
three Raft replicas with persistent storage. Its transit seal points to
`openbao-transit.<local_dns>` and key `openbao-unseal`. The primary UI/API is
exposed at `openbao.<local_dns>`.

### Coder integration addon

`addons/openbao-coder.yaml`

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

### Coder workspace template

`Automation/AI/Coder`

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

## Recovery: Transit-Sealed Primary

### What happened

The primary `openbao` StatefulSet uses Transit OpenBao for auto-unseal. Transit
OpenBao became sealed, so the primary replicas could not decrypt their stored
unseal keys and entered `CrashLoopBackOff`. After Transit was unsealed, the
primary still failed because the Kubernetes Secret `openbao-transit-seal`
contained a token without permission for both Transit operations:

```text
transit/encrypt/openbao-unseal
transit/decrypt/openbao-unseal
```

Recovery was:

1. Unseal Transit OpenBao with three of its five Shamir keys.
2. Create/update policy `openbao-seal` with encrypt and decrypt permissions.
3. Create a new token using a Transit admin token.
4. Replace the Kubernetes Secret token.
5. Delete primary pods one at a time. The StatefulSet uses `OnDelete`, so
   `rollout restart` alone does not replace existing pods.

### Recovery commands

Use the production kubeconfig explicitly:

```bash
export KUBECONFIG="$HOME/.kube/config"
export NS=zero-trust
```

Check Transit status:

```bash
kubectl -n "$NS" exec deploy/openbao-transit -- \
  sh -c 'wget -qO- http://127.0.0.1:8200/v1/sys/seal-status' | jq
```

If Transit reports `"sealed":true`, unseal it three times with three distinct
Shamir keys. Transit listens on HTTP inside the pod:

```bash
kubectl -n "$NS" exec -it deploy/openbao-transit -- \
  sh -c 'VAULT_ADDR=http://127.0.0.1:8200 bao operator unseal'
```

Confirm:

```bash
kubectl -n "$NS" exec deploy/openbao-transit -- \
  sh -c 'wget -qO- http://127.0.0.1:8200/v1/sys/seal-status' | jq '.sealed'
```

Create the seal policy. `TRANSIT_ADMIN_TOKEN` must be a Transit admin/root
token. Never commit it or print it:

```bash
export TRANSIT_ADMIN_TOKEN='replace-with-transit-admin-token'

kubectl -n "$NS" exec -i deploy/openbao-transit -- sh -c '
  read -r VAULT_TOKEN
  cat >/tmp/openbao-seal.hcl <<EOF
path "transit/encrypt/openbao-unseal" {
  capabilities = ["update"]
}
path "transit/decrypt/openbao-unseal" {
  capabilities = ["update"]
}
EOF
  VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$VAULT_TOKEN" \
    bao policy write openbao-seal /tmp/openbao-seal.hcl
' <<< "$TRANSIT_ADMIN_TOKEN"
```

Create a replacement token and update the Kubernetes Secret. The generated
token is stored only in the shell variable and Secret:

```bash
NEW_TOKEN=$(
  kubectl -n "$NS" exec -i deploy/openbao-transit -- \
    sh -c 'read -r VAULT_TOKEN; VAULT_ADDR=http://127.0.0.1:8200 \
      VAULT_TOKEN="$VAULT_TOKEN" bao token create \
      -policy=openbao-seal -format=json' <<< "$TRANSIT_ADMIN_TOKEN" |
  jq -r '.auth.client_token'
)

test -n "$NEW_TOKEN" && test "$NEW_TOKEN" != null || exit 1

kubectl -n "$NS" create secret generic openbao-transit-seal \
  --from-literal=token="$NEW_TOKEN" \
  --dry-run=client -o yaml |
kubectl apply --server-side --force-conflicts -f -
```

Restart primary replicas individually. Wait for each pod to become ready before
continuing. This preserves Raft quorum and avoids deleting persistent volumes:

```bash
kubectl -n "$NS" delete pod openbao-0
kubectl -n "$NS" wait --for=condition=Ready pod/openbao-0 --timeout=180s

kubectl -n "$NS" delete pod openbao-1
kubectl -n "$NS" wait --for=condition=Ready pod/openbao-1 --timeout=180s

kubectl -n "$NS" delete pod openbao-2
kubectl -n "$NS" wait --for=condition=Ready pod/openbao-2 --timeout=180s
```

Verify all replicas:

```bash
kubectl -n "$NS" get pods -l app.kubernetes.io/name=openbao
kubectl -n "$NS" exec openbao-0 -- bao status
```

Clean up local credentials:

```bash
unset TRANSIT_ADMIN_TOKEN NEW_TOKEN
```

### Important safety rules

- Do not delete `data-openbao-*` or `openbao-transit-data` PVCs.
- Do not run `bao operator init`; the clusters are already initialized.
- Do not reuse an invalid token from `openbao-transit-seal`.
- A token lookup may return `403` for the seal token; it only needs encrypt and
  decrypt access on key `openbao-unseal`.
- If no Transit admin token or Shamir keys are available, stop and restore them
  from the OpenBao initialization backup.
