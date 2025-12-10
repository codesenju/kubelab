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
ansible-playbook ../addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/traefik.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/cert-manager.yaml --vault-password-file ~/vault-password.txt
```

### 4. Deploy Applications
```bash
# Browse available addons
ls ../addons/

# Deploy any application
ansible-playbook ../addons/<app-name>.yaml --vault-password-file ~/vault-password.txt
```

## 📦 Available Addons

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
plex_claim_token: "claim-token"

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
ansible-playbook ../addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/minio.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/kube-prometheus-stack.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/tempo.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/mimir.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/obi.yaml --vault-password-file ~/vault-password.txt
```

### GitOps + Security
```bash
cd ansible
ansible-playbook ../addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/cert-manager.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/traefik.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/cnpg.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/authentik.yaml --vault-password-file ~/vault-password.txt
```

### Service Mesh + Advanced Networking
```bash
cd ansible
ansible-playbook ../addons/cilium.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/istio.yaml --vault-password-file ~/vault-password.txt
ansible-playbook ../addons/kube-prometheus-stack.yaml --vault-password-file ~/vault-password.txt
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

## 📚 Documentation

- [Cluster Deployment](docs/cluster-deployment.md) - Proxmox + Kubernetes setup
- [Addon Configuration](docs/addon-config.md) - Customizing applications
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

---

**🎯 For experienced K8s administrators:** Deploy what you need, when you need it. All applications are production-ready with proper RBAC, monitoring, and security configurations.
