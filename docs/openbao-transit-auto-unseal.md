# OpenBao Transit Auto-Unseal Guide

This guide documents current Kubelab OpenBao setup:

- Transit OpenBao: one-node Raft cluster used only for auto-unseal.
- Main OpenBao: three-node Raft cluster used for application secrets.
- Namespace: `zero-trust`.
- Deployment control: Ansible creates Argo CD Applications and Gateway API routes.
- Transit workload: Kustomize overlay at `kustomize/openbao-transit/overlays/prod`.
- Main workload: OpenBao Helm chart configured in `addons/openbao.yaml`.

## Concept

OpenBao encrypts its stored data with a barrier key. On startup, main OpenBao is sealed until it can recover that key.

Transit auto-unseal changes startup flow:

1. Main OpenBao starts sealed.
2. Main OpenBao authenticates to transit using `VAULT_TOKEN`.
3. Transit uses key `openbao-unseal` under mount `transit/`.
4. Transit decrypts the wrapped barrier key.
5. Main OpenBao unseals and joins its Raft cluster.

Transit does not store main OpenBao application secrets. It stores the key material required to unwrap main OpenBao's barrier key.

If transit is unavailable, already-running main OpenBao nodes can continue serving, but restarted or new nodes cannot unseal.

## What Happens If Transit Is Sealed

Transit being sealed is different from transit being deleted:

1. Transit stays reachable at its Service and route.
2. Transit returns sealed/standby errors for operations that require its encryption key.
3. Main OpenBao nodes that are already unsealed normally keep serving existing requests.
4. A main OpenBao node that restarts cannot auto-unseal.
5. A new main OpenBao node cannot complete startup or join Raft until transit is unsealed.
6. Main OpenBao's existing Raft data is not lost; it remains encrypted and unavailable to a sealed node.

Check both systems:

```bash
kubectl -n zero-trust exec deploy/openbao-transit -- bao status
kubectl -n zero-trust exec openbao-0 -- bao status -format=json
```

Unseal transit with its stored recovery material:

```bash
kubectl -n zero-trust exec -it deploy/openbao-transit -- \
  bao operator unseal '<TRANSIT_UNSEAL_KEY>'
```

For the current one-node transit deployment, one valid transit unseal key is sufficient only if transit was initialized with `key-threshold=1`. If a higher threshold was used, provide the required number of distinct recovery keys.

Verify transit:

```bash
kubectl -n zero-trust exec deploy/openbao-transit -- bao status
```

Then verify main OpenBao nodes recover:

```bash
kubectl -n zero-trust get pods -l app.kubernetes.io/name=openbao
kubectl -n zero-trust exec openbao-0 -- bao status -format=json
```

If a main node remains sealed after transit recovery, restart only that affected pod:

```bash
kubectl -n zero-trust delete pod openbao-0
```

Do not delete transit's PVC. The transit key and Raft state are stored there. Deleting it can permanently prevent main OpenBao from unsealing.

## Architecture

```text
main OpenBao StatefulSet
  openbao-0
  openbao-1       -- Raft + transit auto-unseal -->  openbao-transit Service
  openbao-2                                             openbao-transit-Deployment
                                                        one-node Raft
```

Current endpoints:

- Internal transit URL: `http://openbao-transit.zero-trust.svc.cluster.local:8200`
- Auto-unseal URL: `https://openbao-transit.<local_dns>`
- Main UI/API route: `https://openbao.<local_dns>`
- Transit route: `https://openbao-transit.<local_dns>`

TLS terminates at Traefik. OpenBao listeners use HTTP inside the cluster. The main OpenBao transit seal uses HTTPS because it reaches transit through the Traefik Gateway route.

## Prerequisites

- Kubernetes cluster and working `kubectl` context.
- Ansible inventory at `ansible/inventories/prod/hosts.ini`.
- `local_dns`, `gatewayapi_namespace`, and `openbao_transit_token` defined in inventory variables.
- NFS storage available at `192.168.0.16:/mnt/pool2/AppData/openbao-transit`.
- Gateway API and Traefik already installed.
- Argo CD installed and reachable.

Keep `openbao_transit_token` in Ansible vault or another secret store. Never commit the token, root token, or recovery keys.

## Files

### Transit

- `addons/openbao-transit.yaml`
  - Creates `ConfigMap/openbao-transit-config`.
  - Creates Argo CD Application `openbao-transit`.
  - Creates `HTTPRoute/openbao-transit`.
- `kustomize/openbao-transit/base/deployment.yaml`
  - Runs one OpenBao transit pod.
  - Uses `Recreate` strategy because storage is `ReadWriteOnce`.
- `kustomize/openbao-transit/base/service.yaml`
  - Creates `Service/openbao-transit` on port `8200`.
- `kustomize/openbao-transit/base/storage.yaml`
  - Creates the NFS-backed PV and PVC.
- `kustomize/openbao-transit/overlays/prod/kustomization.yaml`
  - Sets namespace to `zero-trust`.
  - Uses image `openbao/openbao:2.7.0`.

### Main OpenBao

- `addons/openbao.yaml`
  - Creates `Secret/openbao-transit-seal`.
  - Creates Argo CD Application `openbao`.
  - Configures three-node Raft.
  - Configures transit auto-unseal.
  - Creates `HTTPRoute/openbao`.

Important main configuration:

```hcl
seal "transit" {
  address         = "https://openbao-transit.<local_dns>"
  key_name        = "openbao-unseal"
  mount_path      = "transit/"
  disable_renewal = "false"
  tls_skip_verify = "false"
}
```

## Deployment

Run from repository root:

```bash
cd /Users/jazziro/codesenju/repos/kubelab
ansible-playbook -i ansible/inventories/prod/hosts.ini \
  addons/openbao-transit.yaml \
  --tags openbao-transit,httproute
```

Then deploy main OpenBao:

```bash
ansible-playbook -i ansible/inventories/prod/hosts.ini \
  addons/openbao.yaml \
  --tags openbao,httproute
```

Check Argo Applications:

```bash
kubectl -n argocd get application openbao-transit openbao
kubectl -n argocd get application openbao-transit openbao \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

## Initialize Transit

Transit must be initialized before main OpenBao can use it.

Check transit pod:

```bash
kubectl -n zero-trust get pods -l app=openbao-transit -o wide
```

Initialize transit once:

```bash
kubectl -n zero-trust exec -it deploy/openbao-transit -- \
  bao operator init -key-shares=1 -key-threshold=1
```

Store the generated unseal key securely. Unseal transit:

```bash
kubectl -n zero-trust exec -it deploy/openbao-transit -- \
  bao operator unseal '<TRANSIT_UNSEAL_KEY>'
```

Confirm transit is ready:

```bash
kubectl -n zero-trust exec deploy/openbao-transit -- bao status
```

Transit must show `Initialized true` and `Sealed false`.

## Configure Transit Key

Authenticate to transit using its admin/root token. Do not put token values directly in shell history when possible.

Enable transit engine:

```bash
kubectl -n zero-trust exec -it deploy/openbao-transit -- \
  bao secrets enable transit
```

Create the key expected by `addons/openbao.yaml`:

```bash
kubectl -n zero-trust exec -it deploy/openbao-transit -- \
  bao write -f transit/keys/openbao-unseal
```

Create a restricted policy for main OpenBao:

```bash
kubectl -n zero-trust exec -i deploy/openbao-transit -- \
  bao policy write openbao-auto-unseal - <<'EOF'
path "transit/encrypt/openbao-unseal" {
  capabilities = ["update"]
}

path "transit/decrypt/openbao-unseal" {
  capabilities = ["update"]
}
EOF
```

Create a token for that policy and place it in Ansible secret variables as `openbao_transit_token`:

```bash
kubectl -n zero-trust exec -it deploy/openbao-transit -- \
  bao token create -policy=openbao-auto-unseal -orphan -period=24h
```

The current playbook writes this token to:

```text
Secret/zero-trust/openbao-transit-seal
```

The Helm release exposes it inside main OpenBao as `VAULT_TOKEN`.

## Initialize Main OpenBao

Deploy main OpenBao and wait for its first pod:

```bash
kubectl -n zero-trust get pods -l app.kubernetes.io/name=openbao -w
```

Initialize the Raft cluster once:

```bash
kubectl -n zero-trust exec -it openbao-0 -- \
  bao operator init -recovery-shares=5 -recovery-threshold=3
```

Save all recovery keys securely. The initial root token is for bootstrap administration only.

Check status:

```bash
kubectl -n zero-trust exec openbao-0 -- bao status -format=json
```

Expected fields:

```text
initialized: true
sealed: false
storage_type: raft
ha_enabled: true
```

## Verify Raft

Use the plural command `list-peers`:

```bash
kubectl -n zero-trust exec openbao-0 -- \
  bao operator raft list-peers
```

Expected result: three peers, normally `openbao-0`, `openbao-1`, and `openbao-2`.

Check workloads and endpoints:

```bash
kubectl -n zero-trust get pods -o wide
kubectl -n zero-trust get endpointslice -l kubernetes.io/service-name=openbao -o wide
kubectl -n zero-trust get endpointslice -l kubernetes.io/service-name=openbao-transit -o wide
```

## Verify Transit Reachability

From inside the cluster:

```bash
kubectl run transit-path-check -n zero-trust --rm -i --restart=Never \
  --image=curlimages/curl -- sh -c \
  'for url in \
    https://openbao-transit.<local_dns>/v1/sys/health \
    http://openbao-transit.zero-trust.svc.cluster.local:8200/v1/sys/health; do
      printf "%s " "$url"
      curl -k --connect-timeout 5 --max-time 10 -sS -o /dev/null \
        -w "HTTP %{http_code}\\n" "$url" || printf "FAILED\\n"
    done'
```

Expected result: HTTP `200` or another valid OpenBao health response for both URLs. A connection or DNS failure indicates routing or Service trouble.

## Test Auto-Unseal

Delete one main OpenBao pod:

```bash
kubectl -n zero-trust delete pod openbao-0
kubectl -n zero-trust get pods -w
```

After it returns `1/1 Running`, verify:

```bash
kubectl -n zero-trust exec openbao-0 -- bao status -format=json
```

Expected:

```text
initialized: true
sealed: false
```

This proves main OpenBao reached transit and recovered its barrier key without manual recovery-key input.

## Troubleshooting

### Main OpenBao says `is the server initialized?`

The cluster has not been initialized yet. Run `bao operator init` once on `openbao-0`.

### Main OpenBao says `Vault is sealed`

Check transit first:

```bash
kubectl -n zero-trust get pod -l app=openbao-transit
kubectl -n zero-trust exec deploy/openbao-transit -- bao status
```

Then test both transit URLs using the reachability command above.

### Main OpenBao cannot resolve `openbao-1.openbao-internal`

This is normal before `openbao-1` exists. After initialization, the StatefulSet should create all three pods. Check:

```bash
kubectl -n zero-trust get statefulset openbao
kubectl -n zero-trust get pods -l app.kubernetes.io/name=openbao
```

### Transit route returns EndpointSlice errors

Check:

```bash
kubectl -n zero-trust get svc openbao-transit
kubectl -n zero-trust get endpointslice \
  -l kubernetes.io/service-name=openbao-transit -o wide
kubectl -n zero-trust get httproute openbao-transit -o yaml
```

Transit Service uses a pod selector, so Kubernetes should create its EndpointSlice automatically.

### TLS errors reach transit

Main OpenBao requires a valid certificate for `openbao-transit.<local_dns>` because `tls_skip_verify = false`. Check Traefik Gateway listeners and certificate configuration before disabling verification.

## Security and Operations

- Store transit unseal key outside the cluster.
- Store main OpenBao recovery keys outside the cluster.
- Do not commit `openbao_transit_token` or generated tokens.
- Replace the initial root token with named admin authentication and revoke the initial token.
- Back up both Raft data stores independently.
- Monitor transit availability because main OpenBao restarts depend on it.
- Test auto-unseal after upgrades and storage changes.
- Keep transit and main OpenBao image versions intentionally selected and documented.
