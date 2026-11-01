# TrueNAS Storage Backend Benchmark — NFS vs iSCSI vs NVMe-oF/TCP

Benchmark comparing the three TrueNAS-backed storage protocols available to the
cluster, run to decide which backend to use for latency-sensitive workloads
(specifically the SigNoz ClickHouse telemetry store, whose dashboard queries were
loading slowly on NFS).

- **Date:** 2026-10-31
- **TrueNAS:** `192.168.0.16` — TrueNAS SCALE **25.10.4**
- **CSI driver:** `csi.truenas.io` (`truenas-csi-driver` v25.10.0)
- **Fabric:** cluster LAN `192.168.0.0/24`
- **Tool:** `fio 3.36`, `--direct=1`, `--ioengine=libaio`, ext4 on each block device
- **Method:** one 10 Gi PVC per storage class, mounted into a single Ubuntu pod on
  `k8s-worker-1`, identical fio profiles against each. All three protocols terminate
  on the **same** TrueNAS appliance and pool, so this isolates the **protocol**, not
  the underlying disks.

> NFS numbers were captured in an earlier run against the same appliance with the
> same fio profiles; iSCSI and NVMe-oF were captured head-to-head in one pod.

## Results (read-focused — matches ClickHouse query patterns)

| Workload | NFS (`nfs-csi`) | iSCSI (`truenas-iscsi`) | **NVMe-oF/TCP (`truenas-nvmeof`)** |
|----------|-----------------|-------------------------|------------------------------------|
| Random read 4k, qd16 (query scans)           | 3,135 IOPS / 5.1 ms   | 28,101 IOPS / 0.57 ms  | **41,052 IOPS / 0.39 ms**  |
| Random read 4k, qd64 ×4 jobs (concurrent queries) | — | 10,133 IOPS / 25.3 ms  | **77,099 IOPS / 3.3 ms**   |
| Sequential read 1M (large part scans)        | 362 MB/s / 22.6 ms    | 1,144 MB/s / 7.2 ms    | **1,825 MB/s / 4.5 ms**    |

*(latency shown is mean per-IO latency)*

### Write note

A 4k random-write + `fsync=1` profile was also run earlier (NFS vs iSCSI). Those
numbers are **not protocol-representative** of ClickHouse — forcing a disk flush on
every 4k op measures sync-durability semantics (which differ between NFS and block
protocols) rather than ClickHouse's batched, async insert path. Reads are the
decision-relevant signal and are reported above.

## Interpretation

- **NFS → iSCSI** is the single biggest jump: random-read IOPS went up ~9× and
  per-IO latency dropped ~9×. NFS is the wrong backend for ClickHouse; escaping it
  captures the majority of the available win.
- **iSCSI → NVMe-oF/TCP** matters most **under concurrency** — the pattern a busy
  SigNoz dashboard produces (many queries at once):
  - NVMe-oF: **77,099 IOPS @ 3.3 ms** vs iSCSI **10,133 IOPS @ 25.3 ms** → **~7.6× more
    IOPS and ~7.6× lower latency**.
  - iSCSI actually *degraded* at high queue depth (single SCSI command queue
    saturates); NVMe-oF's multi-queue design scaled up.
- Sequential throughput also favors NVMe-oF (~1.6× iSCSI, ~5× NFS).

**Verdict:** **NVMe-oF/TCP is the recommended backend for ClickHouse** (and any other
latency-sensitive, concurrency-heavy block workload). iSCSI is a solid second choice
and still vastly better than NFS.

## Prerequisites discovered / configured

Getting NVMe-oF working end-to-end required three gates to be closed:

1. **TrueNAS target service** — NVMe-oF is supported on SCALE 25.10 and the
   NVMe/TCP port (`192.168.0.16:4420`) was configured, but the `nvmet` **service was
   STOPPED and not enabled**. It was started and set to start on boot (the cause of
   the initial `nvme connect: Connection refused`).
2. **Worker kernel module** — the k8s worker VMs (Ubuntu, kernel `5.15.0-202`) did
   not ship `nvme_tcp`. Installed `linux-modules-extra-$(uname -r)` + `nvme-cli`,
   loaded and persisted `nvme_tcp` on all workers via Ansible
   (`storage/truenas/main.yaml`, `--tags nvme`).
3. **StorageClass** — the `csi.truenas.io` driver supports `protocol: nvmeof`; a
   `truenas-nvmeof` StorageClass was added (see below).

## Related IaC

- `kustomize/csi-truenas/base/storageclass-nvmeof.yaml` — vendored NVMe-oF
  StorageClass (from the upstream `master` example; the pinned `v1.0.1` tag used for
  the other StorageClasses does not include it).
- `kustomize/csi-truenas/base/kustomization.yaml` — references the vendored SC.
- `storage/truenas/main.yaml` — kustomize patch customizing `truenas-nvmeof`
  (`datasetPath: k8s/nvmeof`), mirroring the `truenas-iscsi` patch; plus the
  `nvme`-tagged play that installs `nvme_tcp` on workers:
  ```bash
  cd ansible
  export ANSIBLE_CONFIG=ansible.cfg
  ansible-playbook ../storage/truenas/main.yaml -i inventories/prod/hosts.ini --tags nvme
  ```

## How to use `truenas-nvmeof`

```yaml
spec:
  storageClassName: truenas-nvmeof
  accessModes: ["ReadWriteOnce"]   # block, single-attach
  resources:
    requests:
      storage: 20Gi
```
