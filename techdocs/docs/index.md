# IY Synergy homelab

Documentation for the homelab platform, written from observed facts. Figures were collected on 2026-11-21.

| Area | What it covers |
|---|---|
| [Proxmox nodes](infrastructure/proxmox-nodes.md) | Machine models, CPU, RAM, disks and network links, with capacity against allocation |
| [Virtual machines and containers](infrastructure/guests.md) | Every guest, where it runs and what it is allocated |
| [Kubernetes cluster](infrastructure/kubernetes.md) | Nodes, placement and memory use |
| [Storage](infrastructure/storage.md) | Proxmox stores and Kubernetes storage classes |
| [Network](infrastructure/network.md) | Gateway, switch, ingress and serial access |
| [Platform services](services/platform-services.md) | Argo CD applications by area |
| [Applications](applications/index.md) | Self-hosted apps and the media stack |
| [How changes reach the cluster](operations/gitops.md) | GitOps flow and contribution rules |

Addresses and hostnames are left out on purpose, because the source repository is public.
