# Kubernetes Cluster VM Summary

## VM Overview

| VM Name | Node | VM ID | CPUs | RAM (MB) | Disk (GB) | IP Address | Role |
|---------|------|-------|------|----------|-----------|------------|------|
| k8s-lb | kubelab-1 | 4000 | 1 | 1024 | 20 | 192.168.0.40/24 | Load Balancer |
| k8s-control-plane-1 | kubelab-1 | 4001 | 12 | 12288 | 50 | 192.168.0.41/24 | Control Plane |
| k8s-control-plane-2 | kubelab-1 | 4002 | 12 | 12288 | 50 | 192.168.0.42/24 | Control Plane |
| k8s-control-plane-3 | kubelab-2 | 4003 | 6 | 12288 | 50 | 192.168.0.43/24 | Control Plane |
| k8s-worker-1 | kubelab-1 | 5001 | 20 | 16384 | 80 | 192.168.0.51/24 | Worker |
| k8s-worker-2 | kubelab-1 | 5002 | 20 | 16384 | 80 | 192.168.0.52/24 | Worker |
| k8s-worker-3 | kubelab-2 | 5003 | 6 | 20480 | 80 | 192.168.0.53/24 | Worker |

## Resource Distribution by Node

| Node | VMs | Total vCPUs | Total RAM (MB) | Total Disk (GB) |
|------|-----|-------------|----------------|-----------------|
| kubelab-1 | 5 | 65 | 58368 | 280 |
| kubelab-2 | 2 | 12 | 32768 | 130 |
| **Total** | **7** | **77** | **91136** | **410** |

## Common Configuration

- **OS Image:** `local:iso/jammy-server-cloudimg-amd64.img`
- **Datastore:** `local-lvm`
- **Network Bridge:** `vmbr0`
- **DNS Servers:** `192.168.0.15`, `1.1.1.1`
- **Gateway:** `192.168.0.1`
- **SSH User:** `ubuntu`
