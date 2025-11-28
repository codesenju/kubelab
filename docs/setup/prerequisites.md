# Prerequisites

## Required Software

### Local Machine
- **Ansible** 2.9 or higher - [Installation Guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- **OpenTofu** - [Installation Guide](https://opentofu.org/docs/intro/install/)
- **kubectl** - [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **SSH client** - For connecting to cluster nodes

### Infrastructure
- **Proxmox VE** - Virtual environment for hosting VMs
  - [Get Started](https://www.proxmox.com/en/products/proxmox-virtual-environment/get-started)
  - Ubuntu cloud-init image: [Download](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img)

## Network Requirements

### Default Network
The default configuration uses `192.168.0.0/24` network. If your network differs, update:
- `tofu/local.tf`
- `ansible/inventory.ini`

### IP Address Allocation
| Component | IP Address | Purpose |
|-----------|-----------|---------|
| Load Balancer | 192.168.0.40 | API server load balancer |
| Control Plane 1 | 192.168.0.41 | Kubernetes control plane |
| Control Plane 2 | 192.168.0.42 | Kubernetes control plane |
| Worker 1 | 192.168.0.51 | Kubernetes worker node |
| Worker 2 | 192.168.0.52 | Kubernetes worker node |

### Required Ports
- **6443** - Kubernetes API server
- **2379-2380** - etcd server client API
- **10250** - Kubelet API
- **10251** - kube-scheduler
- **10252** - kube-controller-manager
- **80/443** - Ingress traffic

## Storage Requirements

### Proxmox Storage
- Minimum 100GB per VM
- Fast storage recommended (SSD/NVMe)

### NFS Storage (Optional)
If using TrueNAS or external NFS:
- NFS server accessible from cluster network
- Export path configured and accessible
- NFSv3 recommended for compatibility

## Access Requirements

### SSH Access
- SSH key pair generated
- Public key added to cloud-init configuration
- SSH access to all nodes from bastion/local machine

### Proxmox API
- API token or credentials for OpenTofu
- Permissions to create VMs and manage resources

## Minimum Hardware

### Control Plane Nodes
- **CPU**: 2 cores
- **RAM**: 4GB
- **Disk**: 50GB

### Worker Nodes
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 100GB

### Recommended Hardware

### Control Plane Nodes
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 100GB

### Worker Nodes
- **CPU**: 8 cores
- **RAM**: 16GB
- **Disk**: 200GB

## Pre-deployment Checklist

- [ ] Proxmox VE installed and accessible
- [ ] Ubuntu cloud-init image uploaded to Proxmox
- [ ] Network configuration reviewed and updated if needed
- [ ] SSH key pair generated
- [ ] Ansible installed on local machine
- [ ] OpenTofu installed on local machine
- [ ] kubectl installed on local machine
- [ ] Proxmox API credentials configured
- [ ] Sufficient storage available on Proxmox
- [ ] Network ports accessible between nodes

## Next Steps

Once prerequisites are met, proceed to:
1. [Configuration](configuration.md) - Set up secrets and variables
2. [Installation](installation.md) - Deploy the cluster
