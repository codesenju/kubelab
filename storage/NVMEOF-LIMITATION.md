# TrueNAS NVMe-oF: concurrent-controller limit (SCALE 25.10.4)

**Status:** Active limitation as of 2026-10-31, TrueNAS SCALE **25.10.4**.

## Summary

The TrueNAS kernel NVMe/TCP target (`nvmet_tcp`) on SCALE 25.10.4 can only serve
roughly **3 concurrent NVMe-oF controllers** in this cluster before new connections
fail. Plan NVMe-oF (`truenas-nvmeof` StorageClass) for only a **small number of
high-value volumes**. Use `truenas-iscsi` for everything else that needs block storage.

## Symptom

A pod with a `truenas-nvmeof` PVC gets stuck in `Init` / `PodInitializing`. The CSI
node plugin reports:

```
MountVolume.MountDevice failed ... failed to connect to NVMe-oF subsystem ...:4420:
nvme connect failed: Failed to write to /dev/nvme-fabrics: I/O error
could not add new controller: failed to write to nvme-fabrics device
```

On the TrueNAS host, `dmesg` shows the target refusing the connect:

```
nvmet: creating nvm controller 4 for subsystem ...
nvmet: failed to install queue 13 cntlid 4 ret 6
```

The CSI VolumeAttachment succeeds (`attached=true`); the failure is at the
host-side `nvme connect` (NodeStage), not at attach.

## Root cause

- Each worker node has 4 CPUs, so each `nvme connect` opens ~4 I/O queues.
- The kernel `nvmet_tcp` target exposes no max-queue tunable
  (`/sys/module/nvmet_tcp/parameters` has only `idle_poll_period_usecs`,
  `so_priority`, `tls_handshake_timeout`), and the nvmet port `max_queue_size`
  is unset/default.
- With ~4 I/O queues per controller, the target runs out of total I/O queue
  capacity at around queue #13 — i.e. the **4th concurrent controller** fails
  with `ret 6` (Internal Error) while installing its first I/O queue.
- This matches the known NVMe/TCP instability reported against SCALE 25.10.
  Later releases (25.10.6+) update the Linux kernel and may change this; retest
  before assuming the limit still applies after a TrueNAS upgrade.

## What works vs. what fails

- Up to ~3 concurrent `truenas-nvmeof` volumes connect fine (confirmed:
  nexus-postgres, signoz-postgres/clickhouse, crowdsec-postgres).
- The 4th concurrent controller fails as above (hit with coder-postgres).
- Multiple controllers from the **same host NQN** (same node) coexist; the limit
  is on **total I/O queues across all controllers on the target**, not per-node.

## Two fixes that are REQUIRED for NVMe-oF to work at all

These were needed to get NVMe-oF functioning in the first place and are
unrelated to the concurrency ceiling above, but documented here together:

1. **CSI controller must run `--mode=controller`, not the default `--mode=all`.**
   In `all` mode the single controller pod registers only its own node in an
   in-memory map and `ControllerPublishVolume` rejects every other node with
   `node <name> not found`, so volumes only attach on the controller's node.
   Persisted in `storage/truenas/main.yaml` (ArgoCD Application patch on the
   `truenas-csi-controller` Deployment).

2. **CSI node DaemonSet must not schedule onto the `systemk` virtual-kubelet node.**
   The upstream DaemonSet tolerates all taints; the plugin fails on `systemk`
   and corrupts the controller's node registry. Persisted as a kustomize patch
   in `kustomize/csi-truenas/base/patch-csi-node-no-virtual-kubelet.yaml`.

If the target's queue state becomes wedged (e.g. after repeated failed connects),
restart the nvmet service on TrueNAS to clear it:

```
ssh root@<truenas>  midclt call service.restart nvmet
```

Note: this briefly drops all live NVMe-oF sessions; they auto-reconnect, but a
consuming Postgres pod may need a restart.

## Guidance

- **`truenas-nvmeof`**: reserve for a few high-value, high-IO databases
  (current users: nexus, signoz). Keep the total count of concurrent NVMe-oF
  consumers at or below ~3 until TrueNAS is upgraded and re-tested.
- **`truenas-iscsi`**: default choice for other Postgres clusters needing block
  storage. iSCSI (SCST on TrueNAS) does not hit this queue ceiling.
  (Migrated here: coder, immich, postiz, temporal.)
- **Avoid `nfs-csi-postgres`** (the original 1Gi NFS path) for Postgres — it was
  the source of the outage this migration resolved.

## References

- Driver: `truenas/truenas-csi` node plugin v1.4.0, controller manifests v1.0.1.
- TrueNAS NVMe/TCP instability reports (SCALE 25.10) and the 25.10.6 kernel
  update are relevant; verify behavior after any TrueNAS upgrade.
