# Infrastructure Provisioning with OpenTofu

This directory contains OpenTofu configurations for provisioning the Kubernetes cluster infrastructure on Proxmox.

## Initial Setup

### 1. Configure Your Proxmox Node Names

> **Important:** If your Proxmox nodes have different names than `kubelab-1` and `kubelab-2`, you must update the node names in `local.tf` before deploying.

Open `local.tf` and modify the following arrays to match your Proxmox cluster:

```hcl
locals {
  # ... other configuration ...

  # Proxmox node assignment for each VM
  # Replace "kubelab-1" and "kubelab-2" with your actual Proxmox node names
  control_plane_nodes = [
    "kubelab-1", # k8s-control-plane-1
    "kubelab-2", # k8s-control-plane-2
    "kubelab-2", # k8s-control-plane-3
  ]

  worker_nodes = [
    "kubelab-2", # k8s-worker-1
    "kubelab-2", # k8s-worker-2
    "kubelab-2", # k8s-worker-3
  ]
}
```

**How it works:**

- Each array element corresponds to a VM by index (index 0 = VM 1, index 1 = VM 2, etc.)
- The value is the exact Proxmox node name where that VM will be deployed
- You can find your Proxmox node names in the Proxmox web UI (left sidebar) or by running `pvesm status` on your Proxmox host

### 2. Customize VM Resources (Optional)

If your Proxmox nodes have different CPU/memory capacities, you can override resources per VM. If no overrides are specified, the default values are used:

**Default Resources:**

- Workers: `worker_cores = 12`, `worker_memory = 16384` (16GB)
- Control Planes: `control_plane_cores = 6`, `control_plane_memory = 4096` (4GB)

**To override resources for specific VMs**, uncomment and modify these arrays in `local.tf`:

```hcl
locals {
  # ... other configuration ...

  # Per-worker CPU and memory overrides (indexed by worker number - 1)
  # If not specified, defaults to worker_cores (12) and worker_memory (16384)
  worker_cores_override = [
    6,  # k8s-worker-1 on kubelab-1
    6,  # k8s-worker-2 on kubelab-1
    14, # k8s-worker-3 on kubelab-2
  ]

  worker_memory_override = [
    16384, # k8s-worker-1 on kubelab-1
    16384, # k8s-worker-2 on kubelab-1
    16384, # k8s-worker-3 on kubelab-2
  ]

  # Per-control-plane CPU and memory overrides (indexed by control plane number - 1)
  # If not specified, defaults to control_plane_cores (6) and control_plane_memory (4096)
  control_plane_cores_override = [
    6,  # k8s-control-plane-1 on kubelab-1
    6,  # k8s-control-plane-2 on kubelab-1
    6,  # k8s-control-plane-3 on kubelab-2
  ]

  control_plane_memory_override = [
    4096, # k8s-control-plane-1 on kubelab-1
    4096, # k8s-control-plane-2 on kubelab-1
    4096, # k8s-control-plane-3 on kubelab-2
  ]
}
```

**Note:** The array index matches the VM number (index 0 = VM 1, index 1 = VM 2, etc.). If the override arrays are commented out or not defined, all VMs will use the default resource values.

### 3. S3 Backend Setup

The OpenTofu state is stored in an S3-compatible backend using Drive3 (Google Drive exposed as S3-compatible storage).

### Configure Drive3 Credentials

Before running OpenTofu commands, export the following environment variables:

```bash
export AWS_ACCESS_KEY_ID={your-access-key}
export AWS_SECRET_ACCESS_KEY={your-secret-key}
export AWS_DEFAULT_REGION=us-east-1
```

The S3 endpoint is configured to use: `https://drives3.iysynergy.com`

## Network Configuration

### IP Address Assignment

| Node Type         | Hostnames               | IP Addresses    |
| ----------------- | ----------------------- | --------------- |
| Load Balancer     | k8s-lb                  | 192.168.0.40    |
| Control Plane (2) | k8s-control-plane-[1-2] | 192.168.0.41-42 |
| Worker Nodes (2)  | k8s-worker-[1-2]        | 192.168.0.51-52 |

IP addresses are automatically generated using the formula: `${var.net}.${base + index + 1}`

## Virtual Machine Specifications

| Resource  | Control Plane                    | Worker Nodes |
| --------- | -------------------------------- | ------------ |
| CPU Cores | 4                                | 4            |
| Memory    | 6GB                              | 6GB          |
| Disk Size | 25GB                             | 50GB         |
| OS Image  | Ubuntu 22.04 (Jammy) Cloud Image |

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

### Pass .env to system environment variables

```bash
export $(grep -v '^#' .env | xargs)
```

### Initialize OpenTofu

```bash
tofu init
```

### Select workspace

```bash
tofu workspace select -or-create <environment>
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
- `local.tf` - Local variables (node assignments, VM specs, network config)

## Proxmox Provider Configuration

The Proxmox provider is configured to use the local Proxmox API:

```hcl
provider "proxmox" {
  insecure = true  # Disables SSL verification (testing only)
}
```

For production environments, it's recommended to set `insecure = false` and configure proper SSL certificates.
