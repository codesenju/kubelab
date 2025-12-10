# Addon Configuration Guide

## 🎯 Overview

Configuration options and customization for KubeLab addons.

## 🔧 Configuration Methods

### 1. Helm Values
Most applications use Helm charts with custom values in `/helm/` directory:

```bash
# Example: Customize Grafana
vim helm/grafana_values.yaml

# Deploy with custom values
ansible-playbook ../addons/grafana.yaml --vault-password-file ~/vault-password.txt
```

### 2. Kustomize Overlays
Applications with Kustomize configurations in `/kustomize/` directory:

```bash
# Example: Customize MinIO
vim kustomize/minio/overlays/prod/kustomization.yaml

# Deploy with customizations
ansible-playbook ../addons/minio.yaml --vault-password-file ~/vault-password.txt
```

### 3. Ansible Variables
Override default values in `group_vars/all/main.yaml`:

```yaml
# Example overrides
cluster_domain: "local.domain.com"
storage_class: "longhorn"
ingress_class: "traefik"
```

## 📦 Common Configurations

### Ingress and DNS
```yaml
# In secrets.yaml
cloudflare_api_token: "your-token"
cloudflare_email: "your-email@domain.com"

# In main.yaml
base_domain: "yourdomain.com"
cluster_issuer: "letsencrypt-prod"
```

### Storage Configuration
```yaml
# Default storage class
default_storage_class: "longhorn"

# NFS configuration
nfs_server: "192.168.0.16"
nfs_path: "/mnt/pool1/AppData"

# MinIO configuration
minio_storage_size: "100Gi"
minio_replicas: 4
```

### Resource Limits
```yaml
# Default resource limits
default_cpu_request: "100m"
default_memory_request: "128Mi"
default_cpu_limit: "500m"
default_memory_limit: "512Mi"
```

## 🔍 Application-Specific Configuration

### Observability Stack

**Prometheus Stack:**
```yaml
# helm/kube_prometheus_stack_values.yaml
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          resources:
            requests:
              storage: 50Gi

grafana:
  persistence:
    enabled: true
    storageClassName: longhorn
    size: 10Gi
```

**Mimir (Long-term Storage):**
```yaml
# helm/mimir_values.yaml
mimir:
  structuredConfig:
    blocks_storage:
      s3:
        endpoint: minio.minio-system.svc.cluster.local:9000
        bucket_name: mimir-blocks
        access_key_id: ${MINIO_ACCESS_KEY}
        secret_access_key: ${MINIO_SECRET_KEY}
```

**Tempo (Tracing):**
```yaml
# In tempo addon
tempo:
  storage:
    trace:
      backend: s3
      s3:
        endpoint: minio.minio-system.svc.cluster.local:9000
        bucket: tempo-traces
```

### Security & Identity

**Authentik:**
```yaml
# In secrets.yaml
authentik_secret_key: "50-character-secret-key"
authentik_bootstrap_password: "admin-password"
authentik_bootstrap_email: "admin@yourdomain.com"

# Database connection
postgres_host: "postgres-cluster-rw.default.svc.cluster.local"
postgres_db: "authentik"
```

**Cert Manager:**
```yaml
# Cloudflare DNS challenge
cert_manager:
  dns_provider: cloudflare
  cloudflare_api_token: ${CLOUDFLARE_API_TOKEN}
  
# Let's Encrypt configuration
letsencrypt:
  email: "admin@yourdomain.com"
  server: "https://acme-v02.api.letsencrypt.org/directory"
```

### Storage Solutions

**Longhorn:**
```yaml
# Default replica count
longhorn:
  defaultSettings:
    defaultReplicaCount: 2
    defaultDataPath: "/var/lib/longhorn"
    
# Backup configuration
  recurringJobSelector:
    enable: true
    jobList:
      - name: backup
        cron: "0 2 * * *"
        task: backup
        retain: 7
```

**MinIO:**
```yaml
# Distributed mode
minio:
  mode: distributed
  replicas: 4
  
# Storage configuration
  persistence:
    enabled: true
    storageClass: longhorn
    size: 100Gi
    
# Console access
  consoleService:
    type: ClusterIP
```

### DevOps Tools

**Gitea:**
```yaml
# Database configuration
gitea:
  postgresql:
    enabled: false  # Use external CNPG
  
  config:
    database:
      DB_TYPE: postgres
      HOST: postgres-cluster-rw.default.svc.cluster.local:5432
      NAME: gitea
      USER: gitea
      PASSWD: ${POSTGRES_PASSWORD}
```

**ArgoCD:**
```yaml
# RBAC configuration
argocd:
  server:
    config:
      url: https://argocd.yourdomain.com
      
  rbac:
    policy.default: role:readonly
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      g, argocd-admins, role:admin
```

## 🔐 Secrets Management

### Required Secrets by Category

**Core Infrastructure:**
```yaml
argocd_admin_password: "secure-password"
traefik_dashboard_password: "secure-password"
```

**Observability:**
```yaml
grafana_admin_password: "secure-password"
prometheus_admin_password: "secure-password"
alertmanager_slack_webhook: "webhook-url"
```

**Storage:**
```yaml
minio_root_user: "admin"
minio_root_password: "secure-password"
minio_access_key: "access-key"
minio_secret_key: "secret-key"
```

**Security:**
```yaml
authentik_secret_key: "50-character-secret"
authentik_bootstrap_password: "admin-password"
vaultwarden_admin_token: "admin-token"
cloudflare_api_token: "cf-token"
```

### Secrets Rotation
```bash
# Update secrets
ansible-vault edit group_vars/all/secrets.yaml --vault-password-file ~/vault-password.txt

# Redeploy affected applications
ansible-playbook ../addons/<app>.yaml --vault-password-file ~/vault-password.txt
```

## 🌐 Network Configuration

### Ingress Configuration
```yaml
# Traefik configuration
traefik:
  ingressClass:
    enabled: true
    isDefaultClass: true
    
  service:
    type: LoadBalancer
    
  ports:
    web:
      port: 80
      redirectTo: websecure
    websecure:
      port: 443
      tls:
        enabled: true
```

### Service Mesh (Istio)
```yaml
# Istio configuration
istio:
  pilot:
    traceSampling: 1.0
    
  proxy:
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
        
  gateways:
    istio-ingressgateway:
      type: LoadBalancer
```

## 📊 Monitoring Configuration

### Custom Dashboards
```bash
# Add custom Grafana dashboards
mkdir -p helm/grafana/dashboards
# Place JSON dashboard files

# Configure dashboard provider
# In grafana_values.yaml:
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      folder: ''
      type: file
      options:
        path: /var/lib/grafana/dashboards/default
```

### Alert Rules
```yaml
# Custom Prometheus rules
additionalPrometheusRulesMap:
  kubelab-alerts:
    groups:
    - name: kubelab.rules
      rules:
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod {{ $labels.pod }} is crash looping"
```

## 🔧 Troubleshooting Configuration

### Common Issues

**Application not starting:**
```bash
# Check ArgoCD application
kubectl describe application <app-name> -n argocd

# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Check events
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
```

**Configuration not applied:**
```bash
# Force ArgoCD sync
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"sync":{"syncStrategy":{"force":true}}}}'

# Check configuration differences
kubectl get application <app-name> -n argocd -o yaml
```

**Resource constraints:**
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -A

# Adjust resource limits in values files
```

---

**🎯 Pro Tip:** Always test configuration changes in a development environment before applying to production clusters.
