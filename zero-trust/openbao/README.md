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
