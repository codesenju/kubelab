# CrowdSec Setup Guide (k0s / k8s)

This guide is ordered **chronologically** — each step shows what to do, what it depends on, and when tokens/secrets are needed.

---

## Phase 0: Prerequisites

Before touching CrowdSec, ensure these are already in place:

| Prerequisite | Why |
|---|---|
| ArgoCD installed | CrowdSec and Traefik are deployed via ArgoCD Applications |
| Traefik Helm chart deployed | CrowdSec bouncer middleware targets Traefik's LAPI service |
| Gateway API CRDs installed | Traefik uses Gateway API for routing |
| CloudNativePG operator | CrowdSec LAPI uses PostgreSQL managed by CNPG |

---

## Phase 1: Collect External Secrets

These must be obtained **before** writing `secrets.yaml`. No cluster access needed yet.

### 1a. CrowdSec Console Enrollment Key

1. Go to https://app.crowdsec.net
2. Sign in / create an account
3. Click **Enroll command** on the Security Engines page
4. Copy the enrollment key (e.g. `cmrteo9ok000502l4xm0a6yei`)
5. **Save for** → `crowdsec_enroll_key` in secrets.yaml

### 1b. Choose Instance Name and Tags

Pick a name that won't clash with other engines in the same console org:

```yaml
crowdsec_enroll_instance_name: "k0s-cloud"     # or kubelab, prod, etc.
crowdsec_enroll_tags: "linux k8s cloud k0s oci"
```

---

## Phase 2: Write secrets.yaml

Define all CrowdSec secrets in `ansible/inventories/<inventory>/group_vars/all/secrets.yaml`:

```yaml
# ── PostgreSQL (used by CrowdSec LAPI) ──
crowdsec_db_username: "crowdsec_admin"
crowdsec_db_password: "<random-password>"
crowdsec_db_name: "crowdsec"
crowdsec_db_host: "crowdsec-postgres-rw.crowdsec.svc.cluster.local"

# ── Console enrollment (from Phase 1) ──
crowdsec_enroll_key: "cmrteo9ok000502l4xm0a6yei"
crowdsec_enroll_instance_name: "k0s-cloud"
crowdsec_enroll_tags: "linux k8s cloud k0s oci"

# ── Bouncer API key (generated later in Phase 4) ──
crowdsec_lapi_key: "<will-be-filled-after-first-deploy>"

# ── Namespaces that need a CrowdSec bouncer middleware ──
crowdsec_bouncer_namespaces:
  - traefik
  - media-stack
  - argocd
```

> **Note:** `crowdsec_lapi_key` can be any strong random string — you'll generate a matching one in Phase 4.

---

## Phase 3: Deploy CrowdSec (Ansible)

```bash
ansible-playbook addons/crowdsec.yaml
```

This creates (in order):

| # | Resource | Namespace | Depends On |
|---|---|---|---|
| 1 | `Secret/crowdsec-postgres-secrets` | crowdsec | secrets.yaml |
| 2 | `Secret/s3-creds` | crowdsec | secrets.yaml |
| 3 | `Secret/crowdsec-keys` | crowdsec | secrets.yaml (`ENROLL_KEY` + `BOUNCER_KEY_traefik`) |
| 4 | `Secret/crowdsec-bouncer-key` | traefik | secrets.yaml (`BOUNCER_KEY_traefik`) |
| 5 | `Secret/registry-secret` | crowdsec | secrets.yaml |
| 6 | `PGCluster/crowdsec` | crowdsec | #1, #2, #5 |
| 7 | `Application/crowdsec` | argocd | #3, #4, #6 |
| 8 | `Middleware/crowdsec-bouncer` | traefik, media-stack, etc. | #7 (needs LAPI running) |

The ArgoCD Application deploys the CrowdSec Helm chart:
- **Chart:** `crowdsec/crowdsec`
- **Repo:** `https://crowdsecurity.github.io/helm-charts`
- **Version:** `0.24.0`

### Collections Installed

#### AppSec Collections (real-time WAF)

| Collection | Purpose |
|---|---|
| `crowdsecurity/appsec-virtual-patching` | 150+ CVE-specific rules (Log4Shell, Spring4Shell, etc.) |
| `crowdsecurity/appsec-generic-rules` | Generic attack patterns (SSTI, PHP uploads, no User-Agent) |

#### Agent Collections (log parsing + retroactive ban)

| Collection | Purpose |
|---|---|
| `crowdsecurity/traefik` | Parses Traefik access logs for IP-based attack detection |
| `crowdsecurity/base-http-scenarios` | Core HTTP attack scenarios (crawling, probing, path traversal, SQLi, XSS) |
| `crowdsecurity/http-cve` | CVE-specific HTTP attack detection |
| `crowdsecurity/linux` | Linux system log parsing (SSH brute force, etc.) |
| `crowdsecurity/sshd` | SSH daemon log parsing for brute force detection |
| `crowdsecurity/whitelist-good-actors` | Whitelists known good IPs from CrowdSec community |

**Wait for pods to be ready:**

```bash
kubectl get pods -n crowdsec -w
# All pods should reach Running/Ready
```

### Install AppSec Collections on LAPI

The AppSec `COLLECTIONS` env var only installs collections on the AppSec pod. To also have them on the LAPI (for `cscli collections list` visibility and Console sync), install them manually:

```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- \
  cscli collections install crowdsecurity/appsec-generic-rules crowdsecurity/appsec-virtual-patching
```

---

## Phase 4: Generate Bouncer API Key

The bouncer key authenticates Traefik with LAPI. You must create it **after** LAPI is running (Phase 3) and **before** deploying Traefik (Phase 5).

```bash
# 1. Create the bouncer in LAPI
kubectl exec -n crowdsec deploy/crowdsec-lapi -- \
  cscli bouncers add traefik

# 2. Copy the generated API key from the output
#    Example: Api key for 'traefik': <your-key-here>

# 3. Update secrets.yaml with the key
# crowdsec_lapi_key: "<your-key-here>"

# 4. Re-run the playbook to propagate the key to both secrets
ansible-playbook addons/crowdsec.yaml --tags lapi,secrets
```

> **Dependency:** This step requires `crowdsec-lapi` pod to be Running (from Phase 3).

---

## Phase 5: Deploy Traefik (Ansible)

```bash
ansible-playbook addons/traefik-proxy.yaml
```

This creates:

| Resource | Namespace | Depends On |
|---|---|---|
| `Secret/dhi-secret` | traefik | secrets.yaml |
| `Secret/traefik-dashboard-auth` | traefik | secrets.yaml |
| `Middleware/traefik-dashboard-basicauth` | traefik | #1, #2 |
| `Application/traefik-crds` | argocd | Gateway API CRDs |
| `Application/traefik` | argocd | `crowdsec-bouncer-key` secret (Phase 4) |
| `IngressRoute/traefik-dashboard` | traefik | Traefik running |

**Wait for Traefik to be ready:**

```bash
kubectl get pods -n traefik -w
```

> **Dependency:** Requires `crowdsec-bouncer-key` secret with valid `BOUNCER_KEY_traefik` (from Phase 4).

---

## Phase 6: Post-Deployment Console Setup (CRITICAL)

These steps make the bouncer visible in the CrowdSec Console UI. **Without them, the Console shows 0 Remediation Components.**

### 6a. Accept Enrollment in Console

The LAPI auto-enrolls on startup. Visit https://app.crowdsec.net → your engine should appear. Click to accept if prompted.

### 6b. Enable Console Management

```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- \
  cscli console enable console_management
```

### 6c. Fix CAPI Registration (if needed)

If LAPI logs show `"Machine is not enrolled in the console"`:

```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli capi register
kubectl rollout restart deploy/crowdsec-lapi -n crowdsec
kubectl rollout status deploy/crowdsec-lapi -n crowdsec --timeout=60s
```

### 6d. Fix Bouncer `auto_created` Flag

The `BOUNCER_KEY_<name>` env var creates bouncers with `auto_created: false`. The Console only shows bouncers as Remediation Components when `auto_created: true`.

```bash
# Get PostgreSQL password from config
DB_PASS=$(kubectl get cm crowdsec-config-local -n crowdsec \
  -o jsonpath='{.data.config\.yaml\.local}' | \
  grep "password:" | head -1 | awk '{print $2}')

# Find the postgres pod
PG_POD=$(kubectl get pod -n crowdsec -l app=postgresql \
  -o jsonpath='{.items[0].metadata.name}')

# Update auto_created flag
kubectl exec -n crowdsec $PG_POD -c postgres -- \
  env PGPASSWORD="$DB_PASS" psql -U crowdsec_admin -d crowdsec -h 127.0.0.1 \
  -c "UPDATE bouncers SET auto_created = true WHERE name = 'traefik';"

# Verify
kubectl exec -n crowdsec $PG_POD -c postgres -- \
  env PGPASSWORD="$DB_PASS" psql -U crowdsec_admin -d crowdsec -h 127.0.0.1 \
  -c "SELECT name, auto_created, type, version FROM bouncers;"
```

### 6e. Restart LAPI to Sync

```bash
kubectl rollout restart deploy/crowdsec-lapi -n crowdsec
```

**Wait 2-3 minutes**, then verify in the Console UI:
- **Active Remediation Comp.** = 1 (not 0)
- **Active Log Proc.** = >0
- **Scenarios** = installed scenarios listed

---

## Phase 7: Verification

### 7a. Health Checks

```bash
# Pods
kubectl get pods -n crowdsec

# LAPI
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli lapi status

# CAPI
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli capi status

# Console
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli console status

# Bouncer
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers list
```

### 7b. Traefik Plugin

```bash
# Plugin loaded?
kubectl logs -n traefik deploy/traefik | grep -i bouncer

# Middleware accepted?
kubectl get middleware -A

# HTTPRoutes working?
kubectl get httproute -A
```

### 7c. AppSec Rules

```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli appsec-rules list
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli appsec-configs list
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli metrics show appsec
```

### 7d. End-to-End Test

```bash
# Generate attack traffic
for i in $(seq 1 40); do
  curl -k -s -o /dev/null "https://<your-domain>/.env?x=$i"
  curl -k -s -o /dev/null "https://<your-domain>/../../../etc/passwd?x=$i"
  curl -k -s -o /dev/null "https://<your-domain>/shell.php?cmd=id&x=$i"
done

# Wait for scenarios to trigger
sleep 90

# Check alerts
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli alerts list

# Check active bans
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions list
```

### 7e. AppSec Test

```bash
# These should return 403
curl -k -s -o /dev/null -w "%{http_code}\n" "https://<your-domain>/.env"
curl -k -s -o /dev/null -w "%{http_code}\n" "https://<your-domain>/.git/config"
curl -k -s -o /dev/null -w "%{http_code}\n" "https://<your-domain>/this-is-a-appsec-rule-test"
```

---

## How the Middleware Works

The middleware is defined in `addons/crowdsec.yaml:307-333`:

```yaml
spec:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      enabled: true
      crowdsecMode: stream
      crowdsecLapiScheme: http
      crowdsecLapiHost: crowdsec-service.crowdsec.svc.cluster.local:8080
      crowdsecLapiKeyFile: /etc/traefik/crowdsec/BOUNCER_KEY_traefik
      htttTimeoutSeconds: 60
      forwardedheaderstrustedips:
        - 10.0.0.0/8
        - 192.168.0.0/16
        - 10.244.0.0/16
      crowdsecAppsecEnabled: true
      crowdsecAppsecHost: crowdsec-appsec-service.crowdsec.svc.cluster.local:7422
      crowdsecAppsecFailureBlock: true
      crowdsecAppsecUnreachableBlock: true
```

Key points:
- Uses `crowdsecLapiKeyFile` (not `crowdsecLapiKey`) — Traefik reads the key from a mounted file at startup
- The plugin key `crowdsec-bouncer-traefik-plugin` must match the key in `helm/traefik_values.yaml` under `experimental.plugins`
- `crowdsecAppsecEnabled: true` activates the WAF (AppSec) component
- `crowdsecAppsecHost` points to `crowdsec-appsec-service` (NOT `crowdsec-service`) — AppSec runs on a separate service on port 7422
- The middleware must exist **in the same namespace** as the HTTPRoute/IngressRoute that references it

---

## Wiring the Middleware to Routes

### HTTPRoute (Gateway API)

Add a `filters` block in the route rule:

```yaml
spec:
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: crowdsec-bouncer
      backendRefs:
        - name: jellyfin
          port: 8096
```

### IngressRoute (Traefik CRD)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: media-stack
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.example.com`)
      kind: Rule
      middlewares:
        - name: crowdsec-bouncer
          namespace: media-stack
      services:
        - name: myapp
          port: 8080
```

### Ingress (networking.k8s.io)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: media-stack
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: media-stack-crowdsec-bouncer@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

## Adding a New Namespace

If you deploy apps in a different namespace (e.g. `monitoring`, `storage`), add the namespace to `crowdsec_bouncer_namespaces` in secrets.yaml and re-run the playbook, or create the middleware manually:

```bash
kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: crowdsec-bouncer
  namespace: <your-namespace>
spec:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      enabled: true
      crowdsecMode: stream
      crowdsecLapiScheme: http
      crowdsecLapiHost: crowdsec-service.crowdsec.svc.cluster.local:8080
      crowdsecLapiKeyFile: /etc/traefik/crowdsec/BOUNCER_KEY_traefik
      crowdsecAppsecEnabled: true
      crowdsecAppsecHost: crowdsec-appsec-service.crowdsec.svc.cluster.local:7422
      crowdsecAppsecFailureBlock: true
      crowdsecAppsecUnreachableBlock: true
EOF
```

---

## AppSec (WAF) Component

CrowdSec has a separate **AppSec (Web Application Firewall)** component that inspects HTTP requests in real-time — before they reach your applications. While agents parse logs after the fact, AppSec blocks malicious requests immediately.

> **Reference:** [CrowdSec WAF QuickStart for Traefik](https://doc.crowdsec.net/docs/next/appsec/quickstart/traefik)

### Architecture

```
Internet → Traefik (bouncer plugin)
              ├── Step 1: LAPI check (IP ban? stream mode from cache)
              └── Step 2: AppSec check (if crowdsecAppsecEnabled: true)
                    POST http://crowdsec-appsec-service.crowdsec.svc.cluster.local:7422/
                    Headers: x-crowdsec-appsec-ip, x-crowdsec-appsec-uri, etc.
                    Returns: 200 (pass) or 403 (block)
              → Backend Service
```

### AppSec Collections Installed

| Collection | Purpose |
|---|---|
| `crowdsecurity/appsec-virtual-patching` | 150+ CVE-specific rules (Log4Shell, Spring4Shell, etc.) |
| `crowdsecurity/appsec-generic-rules` | Generic attack patterns (SSTI, PHP uploads, no User-Agent) |

### AppSec Service

AppSec runs on a **separate service** (`crowdsec-appsec-service`) on port `7422`:
```bash
kubectl get svc -n crowdsec | grep appsec
# crowdsec-appsec-service   ClusterIP   ...   6060/TCP,7422/TCP
```

### Key Difference: Agent vs AppSec

| | Agent | AppSec |
|---|-------|--------|
| **How** | Parses logs after the fact | Inspects requests in real-time |
| **When** | Post-detection (retroactive ban) | Pre-detection (blocks immediately) |
| **Scope** | Any log source (SSH, Traefik, etc.) | HTTP requests only |
| **Speed** | Ban after scenario overflows (60-90s) | Block on first malicious request |

---

## Notable Fixes

### 1. CrowdSec Argo App Name Bug
The CrowdSec playbook (`crowdsec.yaml`) originally named its Argo CD Application `traefik-crds` (copy-paste error). This was fixed to `crowdsec`.

### 2. Private IP Whitelist (Homelab Fix)
The default CrowdSec whitelist (`/etc/crowdsec/parsers/s02-enrich/whitelists.yaml`) whitelists all private IP ranges (`10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`). In a Kubernetes homelab, all traffic originates from private pod IPs, so **every event gets whitelisted** and no alerts are ever generated.

**Permanent fix** (in `crowdsec.yaml` Helm values):
```yaml
config:
  parsers:
    s02-enrich:
      whitelists.yaml: |
        name: crowdsecurity/whitelists
        description: "Whitelist events from localhost only"
        whitelist:
          reason: "localhost only"
          ip:
            - "::1"
          cidr:
            - "127.0.0.0/8"
```

### 3. Traefik Access Log Format
Traefik must output JSON access logs for CrowdSec's `traefik-logs` parser:
```yaml
additionalArguments:
  - "--accessLog=true"
  - "--accessLog.filePath=/dev/stdout"
  - "--accessLog.format=json"
```

### 4. AppSec Service Mismatch
AppSec runs on a **separate service** (`crowdsec-appsec-service`) on port `7422`, not on `crowdsec-service`. The middleware must use:
```yaml
crowdsecAppsecHost: crowdsec-appsec-service.crowdsec.svc.cluster.local:7422
```

### 5. Plugin Key Mismatch
The middleware plugin key (`spec.plugin.<key>`) must match the key registered in `helm/traefik_values.yaml` under `experimental.plugins`. Both must use `crowdsec-bouncer-traefik-plugin`.

### 6. Auto-Registration CIDR
The `allowed_ranges` in `config.yaml.local` must include the actual pod CIDR (`10.0.0.0/8` for this cluster), not just `10.244.0.0/16`. New pods (like AppSec) will fail to register if their IP isn't in the allowed range.

### 7. "CRITICAL: no logs read" from idle agents
The CrowdSec agent is deployed as a DaemonSet across all worker nodes, but Traefik only runs on one node. Agents on other nodes have no Traefik logs to read.

**Fix:** Added `nodeSelector` to both the CrowdSec agent DaemonSet and Traefik deployment so they run on the same node:

```yaml
# crowdsec.yaml — agent Helm values
agent:
  nodeSelector:
    kubernetes.io/ingress-ready: "true"

# traefik-proxy.yaml — Traefik Helm parameters
- name: deployment.nodeSelector.kubernetes\\.io/ingress-ready
  value: "true"
```

### 8. Bouncer auto_created: false (Console Visibility)

**Problem:** Bouncers created via `BOUNCER_KEY_<name>` env var or `cscli bouncers add` have `auto_created: false`. The CrowdSec Console only shows bouncers as "Remediation Components" when `auto_created: true`.

**Fix:** See Phase 6d — update the PostgreSQL database directly after deployment.

### 9. CAPI Registration Broken After Re-enrollment

**Problem:** Running `cscli console enroll --overwrite` can break the Central API (CAPI) credentials.

**Fix:** See Phase 6c — re-register with `cscli capi register`.

### 10. DNS Resolution for hostNetwork Pods

**Problem:** Pods with `hostNetwork: true` (like Traefik) use the node's DNS, not CoreDNS. If the node's DNS can't resolve internal cluster services, the bouncer plugin fails to reach LAPI.

**Fix:** Add `dnsPolicy: None` with explicit DNS config pointing to CoreDNS first:
```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 10.96.0.10        # CoreDNS ClusterIP
    - 100.100.100.100   # OCI DNS
    - 169.254.169.254   # OCI DNS
```

### 11. Agent Collections YAML Indentation Bug

**Problem:** In `addons/crowdsec.yaml`, the `agent:` key was incorrectly indented under `container_runtime:`, causing a YAML parse error (`mapping values are not allowed in this context`). This prevented ArgoCD from syncing the Helm values, so the agent only had `crowdsecurity/traefik` installed.

**Fix:** Ensure `agent:` is at the same indentation level as `container_runtime:`:
```yaml
# WRONG:
container_runtime: containerd
  agent:           # ← indented under container_runtime (invalid YAML)

# CORRECT:
container_runtime: containerd
agent:             # ← same level as container_runtime
  nodeSelector:
    ...
```

---

## Troubleshooting

### AppSec pod not registering
```bash
kubectl -n crowdsec get cm crowdsec-config-local -o yaml | grep -A5 allowed_ranges
```

### Middleware not reaching AppSec
```bash
kubectl get middleware crowdsec-bouncer -n media-stack -o yaml | grep appsec
kubectl -n crowdsec logs deploy/crowdsec-appsec --tail=50
```

### No 403s on test requests
```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli appsec-rules list
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli metrics show appsec
```

### Bouncer not pulling decisions
```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers list
# last_pull should be recent, not stale
```

### Console shows 0 Remediation Components
Follow Phase 6a through 6e in order.

### Collections not installing (agent COLLECTIONS env var)
The `agent.env COLLECTIONS` in the Helm values may not apply if the DaemonSet was created before the values were updated. Check:
```bash
kubectl exec -n crowdsec <agent-pod> -- printenv COLLECTIONS
```
If it shows only the old value, force a DaemonSet rollout:
```bash
kubectl set env ds/crowdsec-agent -n crowdsec COLLECTIONS="<correct-value>"
```
Or install collections manually via LAPI:
```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- \
  cscli collections install crowdsecurity/base-http-scenarios crowdsecurity/http-cve crowdsecurity/traefik
```

### AppSec collections not on LAPI
The AppSec `COLLECTIONS` env var only installs on the AppSec pod. To show them on the LAPI:
```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- \
  cscli collections install crowdsecurity/appsec-generic-rules crowdsecurity/appsec-virtual-patching
```
