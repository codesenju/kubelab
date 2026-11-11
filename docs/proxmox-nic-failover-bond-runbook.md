# Proxmox NIC Failover Bond Runbook (kubelab-2 / kubelab-3)

Active-backup bonding on the Proxmox hosts so the bridge `vmbr0` (host IP + VM
traffic) survives a NIC failure and lets you swap the cable between the onboard
NIC and a USB ethernet dongle without losing connectivity.

> This is **live Proxmox host configuration** in `/etc/network/interfaces`, NOT
> GitOps/ArgoCD managed. There is no out-of-band console (no IPMI/iDRAC) on these
> hosts — a bad change requires physical access to recover. Always use the
> backup + auto-rollback procedure in §3.

## Table of Contents

- [Scope](#scope)
- [1) Why: USB dongle fragility](#1-why-usb-dongle-fragility)
- [2) Final configuration](#2-final-configuration)
- [3) Safe apply procedure (backup + auto-rollback)](#3-safe-apply-procedure-backup--auto-rollback)
- [4) Verification](#4-verification)
- [5) Failover behaviour & cable swapping](#5-failover-behaviour--cable-swapping)
- [6) 2.5G notes](#6-25g-notes)
- [7) Gotchas](#7-gotchas)

## Scope

- Hosts: `kubelab-2` (`192.168.0.12`), `kubelab-3` (`192.168.0.13`)
- Each host runs Proxmox with VMs that are Kubernetes nodes:
  - kubelab-2 → `k8s-control-plane-2` (VM 4002), `k8s-worker-2` (VM 5002)
  - kubelab-3 → `k8s-control-plane-3` (VM 4003), `k8s-worker-3` (VM 5003)
- `control-plane-2/3` are etcd quorum members. Taking one host's network down
  briefly is tolerable (quorum holds on the remaining members), but never take
  two down at once.
- Toolchain present on both: `bonding` kernel module, `ifupdown2` (`ifreload -a`).

## 1) Why: USB dongle fragility

`vmbr0` carries the host IP and all VM tap interfaces. Originally it bridged a
single NIC. Relying on one link (especially a USB dongle, which can
re-enumerate/reset under load) means a single NIC drop takes the host + its VMs
off the cluster — this matched earlier `control-plane-2/worker-2` "unreachable"
taints.

Fix: an **active-backup bond** of the onboard NIC + the USB dongle. Either link
can carry traffic; the other is a hot standby. `miimon 100` detects carrier loss
and fails over.

## 2) Final configuration

Both hosts use `mode active-backup`, `miimon 100`, `primary_reselect always`.
The **primary** (preferred active) NIC differs per host based on which link is
the intended everyday path.

### kubelab-2 (`/etc/network/interfaces`)

Primary = **USB dongle** (`enx6c6e0702b3b8`); onboard Intel `enp0s31f6` (e1000e,
1G) is the standby.

```
iface enp0s31f6 inet manual
iface enx6c6e0702b3b8 inet manual

auto bond0
iface bond0 inet manual
        bond-slaves enx6c6e0702b3b8 enp0s31f6
        bond-miimon 100
        bond-mode active-backup
        bond-primary enx6c6e0702b3b8

auto vmbr0
iface vmbr0 inet static
        address 192.168.0.12/24
        gateway 192.168.0.1
        bridge-ports bond0
        bridge-stp off
        bridge-fd 0
```

### kubelab-3 (`/etc/network/interfaces`)

Primary = **USB 2.5G dongle** (`enx6c6e0702b42c`); onboard `nic0` (r8169, 1G) is
the standby. The dongle was made primary because it is the 2.5G-capable NIC.

```
iface nic0 inet manual
iface enx6c6e0702b42c inet manual

auto bond0
iface bond0 inet manual
        bond-slaves enx6c6e0702b42c nic0
        bond-miimon 100
        bond-mode active-backup
        bond-primary enx6c6e0702b42c

auto vmbr0
iface vmbr0 inet static
        address 192.168.0.13/24
        gateway 192.168.0.1
        bridge-ports bond0
        bridge-stp off
        bridge-fd 0
```

> **Naming note (kubelab-3):** the onboard NIC is persistently named `nic0`
> (udev `ID_NET_NAME=nic0`; its stable MAC-based altname is `enx6c2b59df6c02`,
> predictable-path name would be `enp1s0`). USB NICs get `enx<MAC>` names from
> `/usr/lib/systemd/network/73-usb-net-by-mac.link`, which are stable per device.

## 3) Safe apply procedure (backup + auto-rollback)

Because there is no remote console, always arm a self-healing rollback before
changing the file. It restores the backup and reloads networking after 180s
**unless cancelled**, so a mistake that cuts SSH recovers on its own.

```bash
H=192.168.0.13   # target host
ssh -i ~/codesenju/kubelab.pem root@$H '
  TS=$(date +%Y%m%d-%H%M%S)
  cp -a /etc/network/interfaces /etc/network/interfaces.bak-$TS
  systemd-run --unit=net-rollback --on-active=180 \
    /bin/sh -c "cp -a /etc/network/interfaces.bak-$TS /etc/network/interfaces && ifreload -a"
'
# 1. edit /etc/network/interfaces to the target bond config
# 2. apply:
ssh -i ~/codesenju/kubelab.pem root@$H 'ifreload -a'
# 3. VERIFY with a FRESH ssh (see §4). If good, cancel the rollback:
ssh -i ~/codesenju/kubelab.pem root@$H 'systemctl stop net-rollback.timer; systemctl reset-failed net-rollback.timer'
```

Backups created during this work (kept on the hosts for rollback):
- kubelab-2: `/etc/network/interfaces.bak-20261111-060028`
- kubelab-3: `/etc/network/interfaces.bak-20261111-060520`, `...-060806`

## 4) Verification

```bash
H=192.168.0.13
ssh -i ~/codesenju/kubelab.pem root@$H '
  ip -br addr show vmbr0                       # host IP present
  cat /proc/net/bonding/bond0 | grep -iE "Mode|Primary Slave|Currently Active|Slave Interface|MII Status"
  ping -c2 192.168.0.1                         # gateway reachable
  qm list                                      # VMs still running
'
# cluster side:
kubectl get nodes | grep -E "control-plane-|worker-"
kubectl get --raw='/readyz?verbose' | grep etcd
```

Expected `bond0`: `Mode: fault-tolerance (active-backup)`, `Currently Active
Slave` = the primary, both slaves listed, active slave `MII Status: up`.

## 5) Failover behaviour & cable swapping

- With `active-backup`, only one slave passes traffic at a time; `miimon 100`
  flips to the other within ~100ms of carrier loss.
- You can move the single cable between the onboard port and the dongle freely —
  the bond follows carrier and keeps `vmbr0`/VMs online.
- `bond-primary` + `primary_reselect always` means the primary NIC reclaims
  "active" whenever its carrier returns. On kubelab-3 the primary is the dongle,
  so plugging the onboard `nic0` back in will NOT demote the dongle; the dongle
  stays active while present.
- Observed clean failover on kubelab-3: moving the cable to the dongle logged
  `bond0: (slave enx...): link status definitely up ... making interface the new
  active one` with no host/VM disruption.

## 6) 2.5G notes

Both dongles are Realtek **RTL8156B** (`0bda:8156`, USB 10/100/1G/2.5G),
enumerated at **SuperSpeed (USB3)**, advertising `2500baseT/Full`. They are
**2.5G-ready**.

Currently both negotiate **1000 Mb/s** because the link partner (switch/router
ports) only advertise up to `1000baseT/Full` — i.e. the upstream ports are 1GbE.
No 2.5G switch is in place yet. When a dongle is connected to a 2.5G-capable
port it auto-negotiates to `2500baseT/Full` with no config change
(`ethtool <iface>` will show `Speed: 2500Mb/s`).

Caveat: the onboard NICs are 1G only (kubelab-2 `enp0s31f6`/e1000e,
kubelab-3 `nic0`/r8169). With a 2.5G switch, the dongle runs 2.5G while active; a
failover to the onboard standby drops to 1G until the dongle link returns.

## 7) Gotchas

- **No out-of-band console** — only recover via the §3 auto-rollback or physical
  access. Never edit these files without the armed rollback.
- **Never reload networking on two hosts at once** — you would risk etcd quorum.
- Use `ifreload -a` (ifupdown2), not `systemctl restart networking`.
- These changes are host-local and **not in git**; this runbook is the record.
- If a dongle is swapped for a different physical unit, its `enx<MAC>` name
  changes — update `bond-slaves`/`bond-primary` accordingly.
