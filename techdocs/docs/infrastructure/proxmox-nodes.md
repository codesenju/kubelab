# Proxmox nodes

Hardware figures were read over SSH from each node on 2026-11-21 (read-only commands: `lscpu`, `dmidecode`, `free`, `lsblk`, `pvesm status`). Guest allocations come from the Proxmox API. Treat everything here as a snapshot.

## Summary

| Node | Machine | CPU | Threads | RAM | Proxmox | Kernel |
|---|---|---|---|---|---|---|
| kubelab-1 | Dell Inc. OptiPlex Micro 7010 | 13th Gen Intel(R) Core(TM) i5-13500T | 20 | 62 GiB | 9.2.24 | 7.0.14-26-pve |
| kubelab-2 | Dell Inc. OptiPlex 7000 | 12th Gen Intel(R) Core(TM) i5-12500T | 12 | 31 GiB | 9.2.21 | 7.0.14-23-pve |
| kubelab-3 | Dell Inc. OptiPlex 3060 | Intel(R) Core(TM) i5-8400T CPU @ 1.70GHz | 6 | 23 GiB | 9.2.24 | 7.0.14-26-pve |

## Capacity against what is allocated

Only running guests are counted. vCPUs can be oversubscribed against threads, but memory cannot safely be.

| Node | Threads | Running guests | vCPUs allocated | RAM total | RAM allocated to guests | RAM available at snapshot |
|---|---|---|---|---|---|---|
| kubelab-1 | 20 | 6 | 45 | 62 GiB | 53 GiB | 18.1 GiB |
| kubelab-2 | 12 | 2 | 10 | 31 GiB | 24 GiB | 7.4 GiB |
| kubelab-3 | 6 | 2 | 12 | 23 GiB | 26 GiB | 4.4 GiB |

## kubelab-1

- **Machine:** Dell Inc. OptiPlex Micro 7010 (board 0KYWH7, BIOS 1.9.0)
- **CPU:** 13th Gen Intel(R) Core(TM) i5-13500T, 1 socket, 14 cores, 20 threads, max 4.6 GHz, VT-x
- **Memory:** 62.5 GiB usable, modules: size=32 GB type=DDR4 speed=3200 MT/s; size=32 GB type=DDR4 speed=3200 MT/s
- **Swap:** 8 GiB
- **Uptime at snapshot:** up 1 day, 12 hours, 7 minutes
- **Graphics:** Intel Corporation AlderLake-S GT1 (rev 0c)

**Disks**

| Device | Model | Size | Bus |
|---|---|---|---|
| sda | WD Blue SA510 2.5 2TB | 1.8T | sata |
| nvme0n1 | PCIe 3.0 1TB | 953.9G | nvme |

**Proxmox storage**

| Name | Type | Total | Used | Use |
|---|---|---|---|---|
| local | dir | 94 GiB | 27 GiB | 28.39% |
| local-lvm | lvmthin | 816 GiB | 281 GiB | 34.46% |

**Network interfaces** (reported link speed)

| Interface | Driver | Link |
|---|---|---|
| enp0s31f6 | e1000e | no link / unknown |
| enp1s0 | r8169 | 2500 Mb/s |

The `vmbr0` bridge and the Tailscale interface are left out: a bridge reports a nominal speed, not a real one.

## kubelab-2

- **Machine:** Dell Inc. OptiPlex 7000 (board 0VNM11, BIOS 1.13.1)
- **CPU:** 12th Gen Intel(R) Core(TM) i5-12500T, 1 socket, 6 cores, 12 threads, max 4.4 GHz, VT-x
- **Memory:** 31.0 GiB usable, modules: size=16 GB type=DDR4 speed=2667 MT/s; size=16 GB type=DDR4 speed=2667 MT/s
- **Swap:** 8 GiB
- **Uptime at snapshot:** up 1 day, 12 hours, 6 minutes
- **Graphics:** Intel Corporation Alder Lake-S GT1 [UHD Graphics 770] (rev 0c)

**Disks**

| Device | Model | Size | Bus |
|---|---|---|---|
| nvme0n1 | WDC PC SN730 SDBQNTY-512G-1001 | 476.9G | nvme |

**Proxmox storage**

| Name | Type | Total | Used | Use |
|---|---|---|---|---|
| local | dir | 94 GiB | 22 GiB | 23.30% |
| local-lvm | lvmthin | 349 GiB | 240 GiB | 68.83% |

**Network interfaces** (reported link speed)

| Interface | Driver | Link |
|---|---|---|
| bond0 | bond | 100 Mb/s |
| enp0s31f6 | e1000e | no link / unknown |
| enx6c6e0702b3b8 | r8152 | 100 Mb/s |

The `vmbr0` bridge and the Tailscale interface are left out: a bridge reports a nominal speed, not a real one.

## kubelab-3

- **Machine:** Dell Inc. OptiPlex 3060 (board 03KWTV, BIOS 1.21.0)
- **CPU:** Intel(R) Core(TM) i5-8400T CPU @ 1.70GHz, 1 socket, 6 cores, 6 threads, max 3.3 GHz, VT-x
- **Memory:** 23.3 GiB usable, modules: size=16 GB type=DDR4 speed=2400 MT/s; size=8 GB type=DDR4 speed=2400 MT/s
- **Swap:** 8 GiB
- **Uptime at snapshot:** up 1 day, 12 hours, 8 minutes
- **Graphics:** Intel Corporation CoffeeLake-S GT2 [UHD Graphics 630]

**Disks**

| Device | Model | Size | Bus |
|---|---|---|---|
| nvme0n1 | 2550 Micron 512GB | 476.9G | nvme |

**Proxmox storage**

| Name | Type | Total | Used | Use |
|---|---|---|---|---|
| local | dir | 94 GiB | 7 GiB | 7.32% |
| local-lvm | lvmthin | 349 GiB | 89 GiB | 25.43% |

**Network interfaces** (reported link speed)

| Interface | Driver | Link |
|---|---|---|
| bond0 | bond | 2500 Mb/s |
| enx6c6e0702b42c | r8152 | 2500 Mb/s |
| nic0 | r8169 | no link / unknown |

The `vmbr0` bridge and the Tailscale interface are left out: a bridge reports a nominal speed, not a real one.

## Observations

- **kubelab-2 uplink:** the bond reports 100 Mb/s through a USB NIC, and the onboard Intel NIC reports no link speed. This node carries a control-plane VM and a worker, so cluster traffic to it is capped at 100 Mb/s.
- **Memory oversubscription on kubelab-3:** running guests are allocated about 26 GiB against 23 GiB usable, and 4 GiB was available at the snapshot. That only works while guests stay below their allocation, so treat this node as full.
- **CPU oversubscription:** kubelab-1 has 45 vCPUs allocated on 20 threads, and kubelab-3 has 12 on 6. CPU can be shared, but expect contention when several guests are busy.
- **kubelab-3 memory:** 24 GiB installed, the smallest node, with 16 GiB + 8 GiB modules at 2400 MT/s. It runs a control-plane VM and a worker.
- **kubelab-1 SATA disk:** the 2 TB SATA SSD is not a Proxmox storage. It is passed through whole to the TrueNAS VM (102) and carries a ZFS pool, so it does not add free space for other guests.
