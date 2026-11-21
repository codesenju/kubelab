# Kubernetes cluster

Six nodes: three control-plane and three workers, all Proxmox VMs. Node data from `kubectl` on 2026-11-21.

| Node | Role | Runs on | CPUs | Memory | Allocatable memory | Memory in use at snapshot | Kubelet |
|---|---|---|---|---|---|---|---|
| k8s-control-plane-1 | control-plane | kubelab-1 | 12 | 5.9 GiB | 5.4 GiB | 6190Mi (111%) | v1.35.8 |
| k8s-control-plane-2 | control-plane | kubelab-2 | 4 | 5.9 GiB | 5.4 GiB | 5919Mi (107%) | v1.35.8 |
| k8s-control-plane-3 | control-plane | kubelab-3 | 6 | 5.9 GiB | 5.4 GiB | 4539Mi (82%) | v1.35.8 |
| k8s-worker-1 | worker | kubelab-1 | 20 | 15.9 GiB | 15.4 GiB | 12010Mi (76%) | v1.35.8 |
| k8s-worker-2 | worker | kubelab-2 | 6 | 11.9 GiB | 11.4 GiB | 6023Mi (51%) | v1.35.8 |
| k8s-worker-3 | worker | kubelab-3 | 6 | 12.0 GiB | 11.5 GiB | 10138Mi (86%) | v1.35.8 |

## Observations

- Control-plane nodes have about 6 GiB of memory each. At the snapshot the first two were at or above 100% of allocatable memory, so they are under pressure.
- Control-plane count is three, so etcd tolerates the loss of one node.
- A load-balancer VM (`k8s-lb`) runs on kubelab-1.
