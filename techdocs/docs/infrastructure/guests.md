# Virtual machines and containers

Guest list and allocations from the Proxmox API on 2026-11-21. Names are shortened where they contained a domain.

| Node | ID | Name | Type | State | vCPUs | RAM | Disk |
|---|---|---|---|---|---|---|---|
| kubelab-1 | 101 | win11 | qemu | stopped | 2 | 4.0 GiB | 64 GiB |
| kubelab-1 | 102 | TrueNAS | qemu | running | 4 | 8.0 GiB | 20 GiB |
| kubelab-1 | 106 | hermes | lxc | running | 2 | 6.0 GiB | 63 GiB |
| kubelab-1 | 2001 | ubuntu | qemu | running | 6 | 12.0 GiB | 110 GiB |
| kubelab-1 | 4000 | k8s-lb | qemu | running | 1 | 1.0 GiB | 20 GiB |
| kubelab-1 | 4001 | k8s-control-plane-1 | qemu | running | 12 | 10.0 GiB | 50 GiB |
| kubelab-1 | 5001 | k8s-worker-1 | qemu | running | 20 | 16.0 GiB | 80 GiB |
| kubelab-2 | 100 | win11 | qemu | stopped | 2 | 4.0 GiB | 64 GiB |
| kubelab-2 | 103 | kali | qemu | stopped | 4 | 6.0 GiB | 52 GiB |
| kubelab-2 | 104 | transmission | lxc | stopped | 1 | 0.6 GiB | 8 GiB |
| kubelab-2 | 105 | mailserver | lxc | stopped | 2 | 4.0 GiB | 20 GiB |
| kubelab-2 | 4002 | k8s-control-plane-2 | qemu | running | 4 | 8.0 GiB | 50 GiB |
| kubelab-2 | 5002 | k8s-worker-2 | qemu | running | 6 | 16.0 GiB | 80 GiB |
| kubelab-2 | 6001 | kiro-gateway | lxc | stopped | 1 | 1.0 GiB | 8 GiB |
| kubelab-3 | 4003 | k8s-control-plane-3 | qemu | running | 6 | 10.0 GiB | 50 GiB |
| kubelab-3 | 5003 | k8s-worker-3 | qemu | running | 6 | 16.0 GiB | 80 GiB |

Stopped guests keep their disk allocation but use no CPU or memory.
