# Infrastructure Provisioning with OpenTofu

This directory contains OpenTofu configurations for provisioning the Kubernetes cluster infrastructure on Proxmox.

## Network Configuration

### IP Address Assignment

| Node Type         | Hostnames               | IP Addresses    |
|-------------------|-------------------------|-----------------|
| Load Balancer     | k8s-lb                  | 192.168.0.40    |
| Control Plane (2) | k8s-control-plane-[1-2] | 192.168.0.41-42 |
| Worker Nodes (2)  | k8s-worker-[1-2]        | 192.168.0.51-52 |

IP addresses are automatically generated using the formula: `${var.net}.${base + index + 1}`

## Virtual Machine Specifications

| Resource        | Control Plane | Worker Nodes |
|----------------|---------------|--------------|
| CPU Cores      | 4             | 4            |
| Memory         | 6GB           | 6GB          |
| Disk Size      | 25GB          | 50GB         |
| OS Image       | Ubuntu 22.04 (Jammy) Cloud Image |

## Authentication Setup

- **Default Credentials**:
  - Username: `ubuntu`
  - Password: `ubuntu`
- **SSH Key Authentication**:
  - Public key path: `./kubelab.pub`

### Generating SSH Keys

```bash
# Generate a new Ed25519 key pair
ssh-keygen -t ed25519 -a 100 -f ./kubelab -C "k8s-cluster-proxmox-key"

# Set appropriate permissions
chmod 600 ./kubelab*
```

## Usage

### Initialize OpenTofu

```bash
tofu init
```

### Plan the Deployment

```bash
tofu plan -out=plan
```

### Apply the Configuration

```bash
tofu apply "plan"
```

### Destroy the Infrastructure

```bash
tofu destroy
```

## Configuration Files

- `main.tf` - Main configuration file
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `local.tf` - Local variables

## Proxmox Provider Configuration

The Proxmox provider is configured to use the local Proxmox API:

```hcl
provider "proxmox" {
  insecure = true  # Disables SSL verification (testing only)
}
```

For production environments, it's recommended to set `insecure = false` and configure proper SSL certificates.
