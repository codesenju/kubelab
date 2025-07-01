# Kubernetes Upgrade Guide

This guide provides step-by-step instructions for upgrading your Kubernetes cluster.

## Upgrading from 1.20.x to 1.30.x

### 1. Update Package Repositories

```bash
# Add the Kubernetes 1.30 repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

# Update package lists
sudo apt-get update

# Install kubeadm
sudo apt-get install -y kubeadm=1.30.12-1.1 --allow-change-held-packages

# Reboot the node
sudo shutdown -r now
```

### 2. Upgrade Control Plane Nodes

#### First Control Plane Node

```bash
# Hold kubeadm at the current version
sudo apt-mark hold kubeadm

# Check upgrade plan
sudo kubeadm upgrade plan

# Apply the upgrade
sudo kubeadm upgrade apply 1.30.12-1.1
```

#### Additional Control Plane Nodes

```bash
# On each additional control plane node
sudo kubeadm upgrade node
```

#### Upgrade kubelet and kubectl

```bash
# Drain the node (run this from a node with kubectl access)
kubectl drain <node-name> --ignore-daemonsets

# Check available versions
apt list -a kubelet
apt list -a kubectl

# Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet='1.30.12-1.1' kubectl='1.30.12-1.1' && \
sudo apt-mark hold kubelet kubectl

# Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Make the node schedulable again
kubectl uncordon <node-name>
```

### 3. Upgrade Worker Nodes

Repeat for each worker node:

```bash
# Upgrade kubeadm
sudo apt-mark unhold kubeadm && \
sudo apt-get update && sudo apt-get install -y kubeadm='1.30.12-1.1' && \
sudo apt-mark hold kubeadm

# Upgrade the node configuration
sudo kubeadm upgrade node

# Drain the node (run this from a node with kubectl access)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet='1.30.12-1.1' kubectl='1.30.12-1.1' && \
sudo apt-mark hold kubelet kubectl

# Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Make the node schedulable again
kubectl uncordon <node-name>
```

### 4. Verify the Upgrade

```bash
# Check node versions
kubectl get nodes

# Verify system pods are running
kubectl get pods -n kube-system
```

## Post-Upgrade Tasks

1. Update any manifests that might be affected by API deprecations
2. Test critical applications
3. Update monitoring and logging configurations if necessary
