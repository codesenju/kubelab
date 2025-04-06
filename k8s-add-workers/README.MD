# Kubernetes Worker Node Addition

## Prerequisites
- OpenTofu installed
- Ansible installed
- Proxmox VE cluster access
- SSH access to control plane node (`k8s-control-plane-1`)

## Step 1: Initialize OpenTofu
```bash
tofu init
```

## Step 2: Create Worker VMs
#### Create default (1 worker)

`tofu plan -out=plan -var="worker_count=3"`

### Create multiple workers (example: 3 workers)
`tofu apply -var="worker_count=3"`

## Step 3: Configure Ansible Inventory
```bash
cd ../ansible
nano inventory.ini
```
### Add your worker nodes (example):
ini
```bash
[workers]
k8s-worker-4 ansible_host=192.168.0.xx
k8s-worker-5 ansible_host=192.168.0.xx
```

## Step 4: Install Dependencies

`ansible all -m ping`

`ansible-playbook worker-dependencies.yaml`

## Step 5: Join Workers to Cluster
`ansible-playbook join-workers.yaml`

## Verification
`ssh k8s-control-plane-1 kubectl get nodes`

## Customization Options
```bash
# Example customized deployment
tofu apply \
  -var="worker_count=2" \
  -var="base_vm_id=6000" \
  -var="network_prefix=10.0.1" \
  -var="proxmox_node=proxmox-02"
```