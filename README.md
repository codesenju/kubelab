# KubeLab - Cloud Native Addon Testing Platform

> **Production-ready Kubernetes cluster with 60+ cloud-native applications for testing and evaluation.**

For experienced Kubernetes administrators who want to quickly deploy and evaluate modern cloud-native tools.

## 🚀 Quick Start

### 1. Deploy Kubernetes Cluster
```bash
# Clone repository
git clone https://github.com/codesenju/kubelab.git
cd kubelab

# Deploy on Proxmox (see cluster deployment guide)
cd tofu && tofu apply
cd ../ansible && ansible-playbook main.yaml --vault-password-file ~/vault-password.txt
```

### 2. Configure Secrets
```bash
# Create vault password
echo "your-vault-password" > ~/vault-password.txt
chmod 600 ~/vault-password.txt

# Create secrets file
cd ansible
ansible-vault create group_vars/all/secrets.yaml --vault-password-file ~/vault-password.txt
```

### 3. Deploy Core Infrastructure
```bash
cd ansible

# Choose your environment inventory
export INVENTORY=inventories/oci/hosts.ini
# export INVENTORY=inventories/prod/hosts.ini

ansible-playbook -i "$INVENTORY" ../addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/traefik.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/cert-manager.yaml --vault-password-file ~/vault-password.txt
```

### 4. Deploy Applications
```bash
# Browse available addons
ls ../addons/

# Deploy any application
ansible-playbook -i "$INVENTORY" ../addons/<app-name>.yaml --vault-password-file ~/vault-password.txt
```

## 📦 Available Addons

All commands in the tables below should be run with an environment inventory, for example:

```bash
export INVENTORY=inventories/oci/hosts.ini
# export INVENTORY=inventories/prod/hosts.ini
ansible-playbook -i "$INVENTORY" <playbook> --vault-password-file ~/vault-password.txt
```

Environment mapping:
- `inventories/oci/hosts.ini` -> OCI VM cluster
- `inventories/prod/hosts.ini` -> Homelab cluster on Proxmox

### Core Infrastructure
| Addon | Purpose | Deployment |
|-------|---------|------------|
| **argocd** | GitOps controller | `ansible-playbook ../addons/argocd.yaml --vault-password-file ~/vault-password.txt` |
| **traefik** | Ingress controller | `ansible-playbook ../addons/traefik.yaml --vault-password-file ~/vault-password.txt` |
| **cert-manager** | TLS automation | `ansible-playbook ../addons/cert-manager.yaml --vault-password-file ~/vault-password.txt` |
| **metallb** | Load balancer | `ansible-playbook ../addons/metallb.yaml --vault-password-file ~/vault-password.txt` |
| **metrics-server** | Resource metrics | `ansible-playbook ../addons/metrics-server.yaml --vault-password-file ~/vault-password.txt` |

### Observability Stack
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **kube-prometheus-stack** | Complete monitoring | - | `ansible-playbook ../addons/kube-prometheus-stack.yaml --vault-password-file ~/vault-password.txt` |
| **grafana** | Dashboards | - | `ansible-playbook ../addons/grafana.yaml --vault-password-file ~/vault-password.txt` |
| **mimir** | Long-term metrics | minio | `ansible-playbook ../addons/mimir.yaml --vault-password-file ~/vault-password.txt` |
| **tempo** | Distributed tracing | minio | `ansible-playbook ../addons/tempo.yaml --vault-password-file ~/vault-password.txt` |
| **obi** | OpenTelemetry collector | prometheus, tempo | `ansible-playbook ../addons/obi.yaml --vault-password-file ~/vault-password.txt` |
| **signoz** | APM platform | - | `ansible-playbook ../addons/signoz.yaml --vault-password-file ~/vault-password.txt` |
| **alloy** | Telemetry pipeline | prometheus | `ansible-playbook ../addons/alloy.yaml --vault-password-file ~/vault-password.txt` |
| **elastic** | Search & analytics | - | `ansible-playbook ../addons/elastic.yaml --vault-password-file ~/vault-password.txt` |
| **opensearch** | Search & analytics | - | `ansible-playbook ../addons/opensearch.yaml --vault-password-file ~/vault-password.txt` |

### Storage & Data
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **minio** | S3-compatible storage | - | `ansible-playbook ../addons/minio.yaml --vault-password-file ~/vault-password.txt` |
| **longhorn** | Distributed storage | - | `ansible-playbook ../addons/longhorn.yaml --vault-password-file ~/vault-password.txt` |
| **cnpg** | PostgreSQL operator | - | `ansible-playbook ../addons/cnpg.yaml --vault-password-file ~/vault-password.txt` |
| **csi-driver-nfs** | NFS storage | nfs-server | `ansible-playbook ../addons/csi-driver-nfs.yaml --vault-password-file ~/vault-password.txt` |

### Security & Identity
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **authentik** | Identity provider | cnpg | `ansible-playbook ../addons/authentik.yaml --vault-password-file ~/vault-password.txt` |
| **vaultwarden** | Password manager | - | `ansible-playbook ../addons/vaultwarden.yaml --vault-password-file ~/vault-password.txt` |
| **external-dns** | DNS automation | dns-provider | `ansible-playbook ../addons/external-dns.yaml --vault-password-file ~/vault-password.txt` |

### DevOps & CI/CD
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **gitea** | Git repository | cnpg | `ansible-playbook ../addons/gitea.yaml --vault-password-file ~/vault-password.txt` |
| **harness** | CI/CD platform | - | `ansible-playbook ../addons/harness.yaml --vault-password-file ~/vault-password.txt` |
| **backstage** | Developer portal | cnpg, gitea | `ansible-playbook ../addons/backstage.yaml --vault-password-file ~/vault-password.txt` |
| **n8n** | Workflow automation | cnpg | `ansible-playbook ../addons/n8n.yaml --vault-password-file ~/vault-password.txt` |

### Networking
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **cilium** | CNI with eBPF | - | `ansible-playbook ../addons/cilium.yaml --vault-password-file ~/vault-password.txt` |
| **istio** | Service mesh | - | `ansible-playbook ../addons/istio.yaml --vault-password-file ~/vault-password.txt` |
| **ingress-nginx** | NGINX ingress | - | `ansible-playbook ../addons/ingress-nginx.yaml --vault-password-file ~/vault-password.txt` |

### Utilities
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **portainer** | Container management | - | `ansible-playbook ../addons/portainer.yaml --vault-password-file ~/vault-password.txt` |
| **goldilocks** | Resource optimization | metrics-server | `ansible-playbook ../addons/goldilocks.yaml --vault-password-file ~/vault-password.txt` |
| **keda** | Event-driven autoscaling | - | `ansible-playbook ../addons/keda.yaml --vault-password-file ~/vault-password.txt` |
| **crossplane** | Infrastructure as code | - | `ansible-playbook ../addons/crossplane.yaml --vault-password-file ~/vault-password.txt` |

### Home & Media
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **media-stack** | Jellyfin, Sonarr, Radarr | longhorn/nfs | `ansible-playbook ../addons/media-stack.yaml --vault-password-file ~/vault-password.txt` |
| **homarr** | Dashboard | - | `ansible-playbook ../addons/homarr.yaml --vault-password-file ~/vault-password.txt` |

### Communication
| Addon | Purpose | Dependencies | Deployment |
|-------|---------|--------------|------------|
| **gotify** | Push notifications | - | `ansible-playbook ../addons/gotify.yaml --vault-password-file ~/vault-password.txt` |
| **ntfy** | Simple notifications | - | `ansible-playbook ../addons/ntfy.yaml --vault-password-file ~/vault-password.txt` |

## 🔐 Required Secrets

Create `ansible/group_vars/all/secrets.yaml` with required secrets:

```yaml
---
# Core
argocd_admin_password: "secure-password"
grafana_admin_password: "secure-password"

# Storage
minio_root_user: "admin"
minio_root_password: "secure-password"
minio_access_key: "access-key"
minio_secret_key: "secret-key"

# Database
postgres_password: "secure-password"

# Authentication
authentik_secret_key: "very-long-secret-key"
authentik_bootstrap_password: "admin-password"
authentik_bootstrap_email: "admin@local.domain.com"

# External Services
cloudflare_api_token: "your-token"
cloudflare_email: "your-email"
jellyfin_claim_token: "claim-token"

# Passwords for other apps
vaultwarden_admin_token: "admin-token"
gitea_admin_password: "admin-password"
gotify_admin_password: "admin-password"
opensearch_admin_password: "admin-password"
```

## 🏗️ Common Deployment Patterns

### Complete Observability Stack
```bash
cd ansible
export INVENTORY=inventories/oci/hosts.ini
ansible-playbook -i "$INVENTORY" ../addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/minio.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/kube-prometheus-stack.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/tempo.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/mimir.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/obi.yaml --vault-password-file ~/vault-password.txt
```

### GitOps + Security
```bash
cd ansible
export INVENTORY=inventories/oci/hosts.ini
ansible-playbook -i "$INVENTORY" ../addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/cert-manager.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/traefik.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/cnpg.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/authentik.yaml --vault-password-file ~/vault-password.txt
```

### Service Mesh + Advanced Networking
```bash
cd ansible
export INVENTORY=inventories/oci/hosts.ini
ansible-playbook -i "$INVENTORY" ../addons/cilium.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/istio.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i "$INVENTORY" ../addons/kube-prometheus-stack.yaml --vault-password-file ~/vault-password.txt
```

## 🔧 Management Commands

```bash
# Check deployment status
kubectl get applications -n argocd

# Access applications (port-forward examples)
kubectl port-forward -n argocd svc/argocd-server 8080:80
kubectl port-forward -n monitoring svc/grafana 3000:80
kubectl port-forward -n minio-system svc/minio-console 9001:9001

# Monitor resources
kubectl top nodes
kubectl top pods -A
```

## ✅ Verification & Testing

Run these after deployment to confirm everything is working. All examples assume the **prod** homelab (`192.168.0.65` gateway, `*.local.homelab.com` DNS).

### 1. Infrastructure Health

```bash
# All nodes ready
kubectl get nodes
# Expected: 3 nodes, all Ready

# All system pods running
kubectl get pods -n kube-system
# Expected: CoreDNS, cilium, metrics-server, etc. all Running

# ArgoCD apps synced & healthy
kubectl get applications -n argocd
# Expected: All apps Synced and Healthy

# No crash-looping pods cluster-wide
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
# Expected: No output (empty = all pods healthy)
```

### 2. Core Infrastructure

```bash
# Traefik running
kubectl get pods -n traefik
# Expected: traefik-* 1/1 Running

# Traefik Gateway programmed
kubectl get gateway -n gateway-infra
# Expected: local-gateway PROGRAMMED=True

# Gateway listening on 192.168.0.65
kubectl get gateway local-gateway -n gateway-infra -o jsonpath='{.status.addresses}'
# Expected: [{"type":"IPAddress","value":"192.168.0.65"}]

# cert-manager ready
kubectl get pods -n cert-manager
# Expected: 3 pods (controller, webhook, cainjector) all Running

# MetalLB assigning IPs
kubectl getIPAddressPool -n metallb-system
# Expected: Pool with 192.168.0.x range
```

### 3. Application Routing (via Traefik)

Test that Traefik routes requests to the correct backends:

```bash
# ArgoCD UI
curl -sk -o /dev/null -w "%{http_code}" https://argocd.local.homelab.com/
# Expected: 200 (or 302 redirect to login)

# Grafana
curl -sk -o /dev/null -w "%{http_code}" https://grafana.local.homelab.com/login
# Expected: 200

# Prometheus
curl -sk -o /dev/null -w "%{http_code}" https://prometheus.local.homelab.com/
# Expected: 200

# Radarr
curl -sk -o /dev/null -w "%{http_code}" https://radarr.local.homelab.com/
# Expected: 302 (redirect to login)

# Sonarr
curl -sk -o /dev/null -w "%{http_code}" https://sonarr.local.homelab.com/
# Expected: 302

# Prowlarr
curl -sk -o /dev/null -w "%{http_code}" https://prowlarr.local.homelab.com/
# Expected: 302

# Jellyseerr (catalog)
curl -sk -o /dev/null -w "%{http_code}" https://catalog.local.homelab.com/
# Expected: 200

# Homarr dashboard
curl -sk -o /dev/null -w "%{http_code}" https://homarr.local.homelab.com/
# Expected: 200

# Nexus
curl -sk -o /dev/null -w "%{http_code}" https://nexus.local.homelab.com/
# Expected: 200

# CloudBeaver
curl -sk -o /dev/null -w "%{http_code}" https://cloudbeaver.local.homelab.com/
# Expected: 200

# Immich (photos)
curl -sk -o /dev/null -w "%{http_code}" https://photos.local.homelab.com/
# Expected: 200

# Proxmox
curl -sk -o /dev/null -w "%{http_code}" https://pve.local.homelab.com/
# Expected: 200

# Transmission
curl -sk -o /dev/null -w "%{http_code}" https://transmission.local.homelab.com/
# Expected: 200 or 401
```

### 4. CrowdSec — AppSec WAF (Real-Time Blocking)

The CrowdSec AppSec component inspects HTTP requests and blocks known attack patterns (`.env` probes, `.git/config` scans, CVE exploits).

```bash
# BLOCKED: .env file access (vpatch-env-access rule)
curl -sk -o /dev/null -w "%{http_code}" https://stream.local.homelab.com/.env
# Expected: 403 Forbidden

# BLOCKED: .git/config access (vpatch-git-config rule)
curl -sk -o /dev/null -w "%{http_code}" https://stream.local.homelab.com/.git/config
# Expected: 403 Forbidden

# BLOCKED: .git/HEAD access
curl -sk -o /dev/null -w "%{http_code}" https://stream.local.homelab.com/.git/HEAD
# Expected: 403 Forbidden

# BLOCKED: env.local access
curl -sk -o /dev/null -w "%{http_code}" https://stream.local.homelab.com/env.local
# Expected: 403 Forbidden

# PASS: Normal request (safe path)
curl -sk -o /dev/null -w "%{http_code}" https://radarr.local.homelab.com/
# Expected: 302 (normal redirect, not blocked)
```

> **Note:** The AppSec component runs as a separate pod (`crowdsec-appsec`) on port 7422. If AppSec is unreachable, requests are blocked by default (`crowdsecAppsecUnreachableBlock: true`). See [crowdsec.md](crowdsec.md) for architecture details.

### 5. CrowdSec — Log-Based Detection

CrowdSec agents parse Traefik access logs and detect attack patterns (path traversal, admin probing, scanner detection).

```bash
# Check alerts generated by CrowdSec
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli alerts list
# Expected: Alerts with kind "waf" (AppSec) and "crowdsec" (log-based)

# Check active bans/decisions
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli decisions list
# Expected: Bans for IPs that triggered multiple alerts

# Verify bouncers registered (Traefik + AppSec)
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli bouncers list
# Expected: 2 bouncers (traefik + crowdsec-appsec-*), both valid

# Verify AppSec collections installed
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli collections list
# Expected: crowdsecurity/appsec-virtual-patching, crowdsecurity/appsec-generic-rules

# Check CrowdSec console enrollment
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli console status
# Expected: custom=enabled, manual=enabled, tainted=enabled

# Check CAPI (Community Blocklist) status
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli capi status
# Expected: Successfully interact with Central API, Pulling community blocklist enabled
```

### 6. CrowdSec — Simulated Attacks

Trigger CrowdSec detection by running attack patterns against any HTTPRoute-backed service:

```bash
# Path traversal probing (triggers http-path-traversal-probing)
for path in "../etc/passwd" "../../etc/shadow" "%2e%2e/etc/passwd"; do
  curl -sk -o /dev/null -w "%{http_code} " "https://radarr.local.homelab.com/$path"
done
# Expected: Multiple 403 or 404 responses

# Wait 10-30 seconds for CrowdSec to process logs, then check:
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli alerts list --since 1m
# Expected: New alerts for http-path-traversal-probing or http-probing

# Admin interface probing (triggers http-admin-interface-probing)
for path in "/admin" "/wp-admin" "/phpmyadmin" "/.env"; do
  curl -sk -o /dev/null -w "%{http_code} " "https://sonarr.local.homelab.com$path"
done

# Wait and check bans
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli decisions list
# Expected: Ban decisions for your IP (if enough alerts accumulated)
```

### 7. Traefik Middleware Status

Verify the CrowdSec middleware is correctly configured in each namespace:

```bash
# Check middleware exists in all protected namespaces
for ns in traefik media-stack nexus; do
  echo "=== $ns ==="
  kubectl -n "$ns" get middleware crowdsec-bouncer -o jsonpath='{.spec.plugin}' | python3 -m json.tool
done
# Expected: Each namespace has exactly one key: "crowdsec-bouncer-traefik-plugin"

# Verify middleware is attached to HTTPRoutes
kubectl get httproutes -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.spec.rules[0].filters[]?.extensionRef.name // "none")"'
# Expected: crowdsec-bouncer for media-stack routes, "none" for routes without middleware
```

### 8. Storage

```bash
# Longhorn volumes ready
kubectl get volumes.longhorn.io -A
# Expected: Volumes in Bound/Available state

# PVCs bound (cluster-wide)
kubectl get pvc -A | grep -v STATUS
# Expected: All PVCs Bound

# PostgreSQL clusters healthy (CNPG)
kubectl get clusters -A
# Expected: All clusters Healthy

# MinIO / RustFS running
kubectl get pods -n minio-system
# Expected: Pods Running
```

### 9. Monitoring

```bash
# Prometheus targets up
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# Then open http://localhost:9090/targets — all targets should be UP

# Grafana dashboards
kubectl port-forward -n monitoring svc/grafana 3000:80 &
# Then open http://localhost:3000 — login with admin credentials

# Check Prometheus is scraping targets
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json, sys
data = json.load(sys.stdin)
active = [t for t in data['data']['activeTargets'] if t['health'] == 'up']
print(f'{len(active)} targets UP')
"
```

### 10. Full Smoke Test Script

Run all critical checks in one go:

```bash
#!/bin/bash
GATEWAY="192.168.0.65"
FAIL=0

check() {
  local name=$1 url=$2 expected=$3
  actual=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    echo "  PASS  $name ($actual)"
  else
    echo "  FAIL  $name (expected $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Infrastructure ==="
check "ArgoCD"      "https://argocd.local.homelab.com/"           "200"
check "Grafana"     "https://grafana.local.homelab.com/login"     "200"
check "Prometheus"  "https://prometheus.local.homelab.com/"       "200"
check "Nexus"       "https://nexus.local.homelab.com/"            "200"
check "Homarr"      "https://homarr.local.homelab.com/"           "200"
check "Immich"      "https://photos.local.homelab.com/"           "200"

echo ""
echo "=== Media Stack ==="
check "Radarr"      "https://radarr.local.homelab.com/"           "302"
check "Sonarr"      "https://sonarr.local.homelab.com/"           "302"
check "Prowlarr"    "https://prowlarr.local.homelab.com/"         "302"
check "Jellyseerr"  "https://catalog.local.homelab.com/"          "200"
check "Tdarr"       "https://tdarr.local.homelab.com/"            "200"

echo ""
echo "=== CrowdSec AppSec WAF ==="
check ".env blocked"       "https://radarr.local.homelab.com/.env"         "403"
check ".git/config blocked" "https://radarr.local.homelab.com/.git/config" "403"
check ".git/HEAD blocked"  "https://radarr.local.homelab.com/.git/HEAD"    "403"
check "Normal request"     "https://radarr.local.homelab.com/"             "302"

echo ""
echo "=== External Services ==="
check "Proxmox"      "https://pve.local.homelab.com/"              "200"
check "Pi-hole"      "https://pihole.local.homelab.com/"           "200"
check "HomeAssistant" "https://smarthome.local.homelab.com/"       "200"
check "Transmission" "https://transmission.local.homelab.com/"     "200"

echo ""
if [ $FAIL -eq 0 ]; then
  echo "All checks passed!"
else
  echo "$FAIL check(s) failed"
fi
```

### Known Issues

| Issue | Status | Workaround |
|-------|--------|------------|
| **Tempo Ingress hijacks `*.local.homelab.com` traffic** | Bare Ingress in `tempo` namespace (no host, `path: /`) catches all requests, returning 503 for Jellyfin and others | Add a hostname to the Ingress or replace with HTTPRoute |
| **Nexus registry returns 503** | `registry.local.homelab.com` intermittently unavailable, prevents new pod image pulls | Ensure Nexus is running; scale down stuck ReplicaSets |
| **`local-example-com-tls` secret missing** | Traefik dashboard IngressRoute can't serve HTTPS | Create the TLS secret via cert-manager or manually |
| **CrowdSec console shows 0 alerts** | PAPI (Push API) restricted on COMMUNITY plan | Expected — alerts only visible via `cscli alerts list` locally |

## Building container image
```bash
docker build \
  $(grep -v '^#' .env.production | xargs -I {} echo --build-arg {}) \
  -f Dockerfile \
  -t registry.gitlab.com/iysynergy/imbizo:prod-test .
```

## 📚 Documentation

- [Cluster Deployment](docs/cluster-deployment.md) - Proxmox + Kubernetes setup
- [Addon Configuration](docs/addon-config.md) - Customizing applications
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [CrowdSec Setup](crowdsec.md) - WAF, AppSec, bouncer key management, pentest guide

---

**🎯 For experienced K8s administrators:** Deploy what you need, when you need it. All applications are production-ready with proper RBAC, monitoring, and security configurations.
