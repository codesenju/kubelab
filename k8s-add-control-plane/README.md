# Kubernetes Control Plane Node Addition

## Prerequisites
- OpenTofu installed
- Ansible installed
- Proxmox VE cluster access
- SSH access to control plane node (`k8s-control-plane-1`)
- Existing Kubernetes cluster with at least one control plane node

## Step 1: Initialize OpenTofu
```bash
cd tofu
tofu init
```

## Step 2: Create Control Plane VMs
#### Create default (1 control plane)

`tofu plan -out=plan`

`tofu apply`

### Create multiple control plane nodes (example: 3 control planes)
`tofu apply -var="control_plane_count=3"`

## Step 3: Configure Ansible Inventory
```bash
cd ../ansible
nano inventory.ini
```
### Add your new control plane nodes (example):
ini
```bash
[new_control_plane]
k8s-control-plane-2 ansible_host=192.168.0.42
k8s-control-plane-3 ansible_host=192.168.0.43
```

## Step 4: Install Dependencies

`ansible all -m ping`

`ansible-playbook control-plane-dependencies.yaml`

## Step 5: Join Control Plane to Cluster
ansible-playbook join-control-plane.yaml

### Using a different existing control plane node
By default, the playbook uses `k8s-control-plane-1` to get the join token. To use a different existing control plane node:

ansible-playbook join-control-plane.yaml -e "existing_control_plane_node=k8s-control-plane-2"

## Verification
`ssh k8s-control-plane-1 kubectl get nodes`

## Customization Options
```bash
# Example customized deployment
tofu apply \
  -var="control_plane_count=2" \
  -var="base_vm_id=5000" \
  -var="network_prefix=10.0.1" \
  -var="proxmox_node=proxmox-02"
```

## Note
Adding new control plane nodes requires the certificate key from the existing control plane. The `join-control-plane.yaml` playbook automatically retrieves this key.
