# OpenTofu Proxmox Cluster Configuration

## Network Configuration

### IP Address Assignment
Automatically generated IP addresses for cluster nodes:

| Node Type         | Hostnames               | IP Addresses        |
|-------------------|-------------------------|---------------------|
| Load Balancer     | k8s-lb                  | 192.168.0.40        |
| Control Plane (2) | k8s-control-plane-[1-2] | 192.168.0.41-42     |
| Worker Nodes (2)  | k8s-worker-[1-2]        | 192.168.0.51-52     |

*IP generation formula:* `${var.net}.${base + index + 1}`

## Virtual Machine Specifications

| Resource        | Control Plane | Worker Nodes |
|----------------|---------------|-------------|
| CPU Cores      | 4             | 4           |
| Memory         | 6GB           | 6GB         |
| Disk Size      | 25GB          | 50GB        |
| OS Image       | Ubuntu 22.04 (Jammy) Cloud Image |

## Authentication Setup

- **Default Credentials:**
  - Username: `ubuntu`
  - Password: `ubuntu`
- **SSH Key Authentication:**
  - Public key path: `<your-path>/kubelab.pub`

### Generating a Secure ED25519 Key Pair
To create a modern SSH key pair using the Ed25519 algorithm:

```bash
# Generate a new Ed25519 key pair (will create kubelab and kubelab.pub)
ssh-keygen -t ed25519 -a 100 -f ./kubelab -C "k8s-cluster-proxmox-key"

# Set appropriate permissions
chmod 600 ./kubelab*
```
## Proxmox Provider Configuration

### Current Settings
```hcl
provider "proxmox" {
  insecure = true  # Disables SSL verification (testing only)
}