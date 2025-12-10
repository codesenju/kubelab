# Kubernetes Cluster Deployment on Proxmox

## 🎯 Overview

Deploy a production-ready Kubernetes cluster on Proxmox using OpenTofu and Ansible.

**Architecture:**
- 2x Control Plane nodes (HA)
- 2x Worker nodes
- 1x Load Balancer (HAProxy)
- External storage (TrueNAS NFS)

## 📋 Prerequisites

### Proxmox Environment
- Proxmox VE 8.0+
- Ubuntu 22.04 LTS template
- Available IP range (e.g., 192.168.0.40-60)
- SSH key access

### Local Tools
```bash
# Install required tools
# OpenTofu
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh

# Ansible
pip3 install ansible kubernetes

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

## 🚀 Deployment Steps

### 1. Configure Infrastructure
```bash
# Clone repository
git clone https://github.com/codesenju/kubelab.git
cd kubelab

# Configure Proxmox credentials
cd tofu
cp terraform.tfvars.example terraform.tfvars
# Edit with your Proxmox details
```

### 2. Deploy VMs
```bash
# Initialize and deploy
tofu init
tofu plan
tofu apply

# Note the IP addresses assigned
```

### 3. Configure Ansible Inventory
```bash
cd ../ansible
cp inventory.ini.example inventory.ini

# Edit inventory with VM IPs:
[control_plane]
k8s-control-plane-1 ansible_host=192.168.0.41
k8s-control-plane-2 ansible_host=192.168.0.42

[workers]
k8s-worker-1 ansible_host=192.168.0.51
k8s-worker-2 ansible_host=192.168.0.52

[lb]
k8s-lb ansible_host=192.168.0.40
```

### 4. Create Secrets
```bash
# Create vault password
echo "your-secure-password" > ~/vault-password.txt
chmod 600 ~/vault-password.txt

# Create secrets file
ansible-vault create group_vars/all/secrets.yaml --vault-password-file ~/vault-password.txt

# Add minimal secrets:
---
# Cluster configuration
cluster_name: kubelab
kubernetes_version: "1.28.0"

# Load balancer
lb_vip: "192.168.0.40"

# Storage (if using TrueNAS)
nfs_server: "192.168.0.16"
nfs_path: "/mnt/pool1/AppData"
```

### 5. Deploy Kubernetes
```bash
# Test connectivity
ansible all -m ping

# Deploy cluster
ansible-playbook main.yaml --vault-password-file ~/vault-password.txt

# Deployment includes:
# - OS hardening and updates
# - Container runtime (containerd)
# - Kubernetes components
# - CNI (Cilium)
# - Load balancer configuration
```

### 6. Configure kubectl
```bash
# Copy kubeconfig from control plane
scp ubuntu@192.168.0.41:~/.kube/config ~/.kube/config

# Test cluster access
kubectl get nodes
kubectl get pods -A
```

## ✅ Verification

### Cluster Health
```bash
# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check cluster info
kubectl cluster-info

# Test DNS
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default
```

### Load Balancer
```bash
# Test API server access through LB
curl -k https://192.168.0.40:6443/version

# Check HAProxy stats (if configured)
curl http://192.168.0.40:8404/stats
```

### Storage (if NFS configured)
```bash
# Test NFS mount
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-csi
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-nfs
```

## 🔧 Post-Deployment

### Install Core Components
```bash
cd ansible

# GitOps controller
ansible-playbook ../addons/argocd.yaml --vault-password-file ~/vault-password.txt

# Ingress controller
ansible-playbook ../addons/traefik.yaml --vault-password-file ~/vault-password.txt

# Certificate management
ansible-playbook ../addons/cert-manager.yaml --vault-password-file ~/vault-password.txt

# Metrics
ansible-playbook ../addons/metrics-server.yaml --vault-password-file ~/vault-password.txt
```

### Access ArgoCD
```bash
# Port forward to ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Get admin password
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode

# Login: admin / <password>
# URL: http://localhost:8080
```

## 🚨 Troubleshooting

### Common Issues

**Nodes not joining cluster:**
```bash
# Check kubelet logs
sudo journalctl -u kubelet -f

# Reset node and rejoin
sudo kubeadm reset
# Re-run ansible playbook
```

**Pod networking issues:**
```bash
# Check CNI pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Restart CNI if needed
kubectl delete pods -n kube-system -l k8s-app=cilium
```

**Storage issues:**
```bash
# Check NFS connectivity
showmount -e 192.168.0.16

# Test mount manually
sudo mount -t nfs 192.168.0.16:/mnt/pool1/AppData /mnt/test
```

## 📊 Cluster Specifications

### Default Configuration
- **Kubernetes**: v1.28+
- **CNI**: Cilium
- **CRI**: containerd
- **Load Balancer**: HAProxy
- **Storage**: NFS CSI + local storage
- **Ingress**: Traefik
- **GitOps**: ArgoCD

### Resource Allocation
- **Control Plane**: 4 vCPU, 8GB RAM, 50GB disk
- **Workers**: 8 vCPU, 16GB RAM, 100GB disk
- **Load Balancer**: 2 vCPU, 4GB RAM, 20GB disk

### Network Configuration
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12
- **API Server**: 192.168.0.40:6443 (via LB)
- **Ingress**: 192.168.0.40:80/443 (via LB)

---

**🎯 Result:** Production-ready Kubernetes cluster ready for cloud-native application deployment and testing.
