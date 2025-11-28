# Installation Guide

## Overview

This guide walks through deploying the complete Kubelab environment from infrastructure provisioning to application deployment.

## Step 1: Deploy Infrastructure with OpenTofu

### Initialize OpenTofu
```bash
cd tofu
tofu init
```

### Review Planned Changes
```bash
tofu plan -out=plan
```

Review the output to ensure VMs will be created with correct specifications.

### Apply Configuration
```bash
tofu apply "plan"
```

This will create:
- 2 control plane VMs
- 2 worker VMs
- 1 load balancer VM

### Verify VMs
```bash
# Check Proxmox UI or use CLI
tofu show
```

## Step 2: Verify Ansible Connectivity

```bash
cd ../ansible

# Test connectivity to all nodes
ansible all -m ping

# Expected output: SUCCESS for all nodes
```

If connectivity fails, check:
- SSH keys are properly configured
- VMs are running and accessible
- Inventory file has correct IP addresses

## Step 3: Deploy Kubernetes Cluster

### Deploy Complete Stack
```bash
ansible-playbook main.yaml --vault-pass-file=vault-pass.txt
```

This playbook will:
1. Configure all nodes
2. Install Kubernetes components
3. Initialize control plane
4. Join worker nodes
5. Deploy CNI (Cilium)
6. Deploy CSI (OpenEBS)

### Deploy Specific Components
```bash
# Deploy only Kubernetes
ansible-playbook main.yaml --tags k8s --vault-pass-file=vault-pass.txt

# Deploy only storage
ansible-playbook main.yaml --tags storage --vault-pass-file=vault-pass.txt
```

## Step 4: Configure kubectl Access

### Copy kubeconfig from Control Plane
```bash
# From your local machine
ssh ubuntu@192.168.0.41 cat ~/.kube/config > ~/.kube/config

# Or using scp
scp ubuntu@192.168.0.41:~/.kube/config ~/.kube/config
```

### Verify Cluster Access
```bash
# Check nodes
kubectl get nodes

# Expected output: All nodes in Ready state
# NAME                  STATUS   ROLES           AGE   VERSION
# k8s-control-plane-1   Ready    control-plane   10m   v1.28.x
# k8s-control-plane-2   Ready    control-plane   10m   v1.28.x
# k8s-worker-1          Ready    <none>          9m    v1.28.x
# k8s-worker-2          Ready    <none>          9m    v1.28.x

# Check all pods
kubectl get pods -A

# Check storage classes
kubectl get sc
```

## Step 5: Deploy Core Infrastructure

### Deploy ArgoCD
```bash
ansible-playbook addons/argocd.yaml --vault-pass-file=vault-pass.txt
```

Wait for ArgoCD to be ready:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### Deploy Cert Manager
```bash
ansible-playbook addons/cert-manager.yaml --vault-pass-file=vault-pass.txt
```

### Deploy External DNS
```bash
ansible-playbook addons/external-dns.yaml --vault-pass-file=vault-pass.txt
```

### Deploy Traefik Ingress
```bash
ansible-playbook addons/traefik.yaml --vault-pass-file=vault-pass.txt
```

### Deploy MinIO
```bash
ansible-playbook addons/minio.yaml --vault-pass-file=vault-pass.txt
```

## Step 6: Deploy Observability Stack

### Create MinIO Buckets
```bash
ansible-playbook fix-mimir-buckets.yaml --vault-pass-file=vault-pass.txt
```

### Deploy Mimir
```bash
ansible-playbook addons/mimir.yaml --vault-pass-file=vault-pass.txt
```

Verify Mimir pods:
```bash
kubectl get pods -n mimir
```

### Deploy Tempo
```bash
ansible-playbook addons/tempo.yaml --vault-pass-file=vault-pass.txt
```

### Deploy Loki
```bash
ansible-playbook addons/loki.yaml --vault-pass-file=vault-pass.txt
```

## Step 7: Deploy Monitoring

### Deploy Prometheus Stack
```bash
ansible-playbook addons/kube-prometheus-stack.yaml --vault-pass-file=vault-pass.txt
```

This includes:
- Prometheus
- Alertmanager
- Grafana
- Node Exporter
- Kube State Metrics

### Deploy Grafana (if not included in Prometheus stack)
```bash
ansible-playbook addons/grafana.yaml --vault-pass-file=vault-pass.txt
```

## Step 8: Verify Installation

### Check All Namespaces
```bash
kubectl get pods -A
```

### Check ArgoCD Applications
```bash
kubectl get applications -n argocd
```

All applications should show:
- SYNC STATUS: Synced
- HEALTH STATUS: Healthy

### Access Dashboards

Get ArgoCD admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access dashboards:
- **ArgoCD**: https://argocd.local.example.com
- **Grafana**: https://grafana.local.example.com
- **Prometheus**: https://prometheus.local.example.com

## Step 9: Deploy Applications (Optional)

### Deploy Individual Applications
```bash
ansible-playbook addons/<application-name>.yaml --vault-pass-file=vault-pass.txt
```

### Available Applications
See [Available Applications](../applications.md) for the complete list.

## Post-Installation Tasks

### Enable Volume Expansion
```bash
ansible-playbook main.yaml --tags adhoc,enable_volume_expansion --vault-pass-file=vault-pass.txt
```

### Create Docker Registry Secret (if needed)
```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

### Configure Backup (Recommended)
Set up regular backups of:
- etcd data
- Persistent volumes
- Configuration files

## Troubleshooting Installation

### Pods Not Starting
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### ArgoCD Not Syncing
```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
```

### Certificate Issues
```bash
kubectl get certificates -A
kubectl describe certificate <cert-name> -n <namespace>
```

For more troubleshooting, see [Troubleshooting Guide](../troubleshooting.md).

## Next Steps

- [Configure Monitoring](../guides/monitoring-setup.md)
- [Deploy Applications](../guides/argocd-applications.md)
- [Set Up Storage](../guides/storage-configuration.md)
