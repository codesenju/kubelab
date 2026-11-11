# Media Stack Config → TrueNAS iSCSI Migration Runbook

Moving the *arr app config volumes (SQLite databases) off the shared RWX NFS
volume onto dedicated TrueNAS **iSCSI** block volumes, plus the related
NVMe-oF / Nexus-registry recovery that this work surfaced.

## Table of Contents

- [Scope](#scope)
- [Background: why move config off NFS](#background-why-move-config-off-nfs)
- [Architecture](#architecture)
- [1) Repo changes (GitOps source of truth)](#1-repo-changes-gitops-source-of-truth)
- [2) Migration cutover procedure](#2-migration-cutover-procedure)
- [3) RWO rolling-update deadlock (and how to break it)](#3-rwo-rolling-update-deadlock-and-how-to-break-it)
- [4) Verification](#4-verification)
- [5) Related incident: NVMe-oF mount + Nexus Postgres crash loop](#5-related-incident-nvme-of-mount--nexus-postgres-crash-loop)
- [6) Operational notes & gotchas](#6-operational-notes--gotchas)

## Scope

- Kubernetes namespace: `media-stack`
- Apps migrated: `radarr`, `sonarr`, `qbittorrent` (others remain on NFS)
- GitOps: Ansible (`addons/media-stack.yaml`) → ArgoCD `Application` →
  `kustomize/media-stack/overlays/production`
- NAS: TrueNAS SCALE at `192.168.0.16` (pool `pool2`)
- Storage transports in play: NFS (RWX), iSCSI (RWO block), NVMe-oF (RWO block)

## Background: why move config off NFS

The shared `media-stack-config` PVC is RWX NFS (`192.168.0.16:/mnt/pool2/AppData`),
mounted by every app at `/config` via `subPath: <app>/config`.

The *arr apps keep **SQLite** databases under `/config`. SQLite on NFS suffers
from file-locking stalls and periodic corruption. Observed symptoms before the
migration:

- `radarr.db.pre-repair-*` / `sonarr.db.pre-repair-*` backup files (prior auto-repairs)
- API hangs / readiness-probe timeouts under I/O load
- One NAS pool saturating during large copies stalled every app sharing it

The large media library (`media-data`, also NFS RWX) stays on NFS — it holds no
databases and needs concurrent multi-pod reads. Only **config** moved.

## Architecture

| Volume | Type | Access | Backend | Used by |
|--------|------|--------|---------|---------|
| `media-data` | NFS | RWX | `192.168.0.16:/mnt/pool2/jellyfin/media` | all apps `/data` |
| `media-stack-config` | NFS | RWX | `192.168.0.16:/mnt/pool2/AppData` | apps still on NFS (`subPath: <app>/config`) |
| `radarr-config` | iSCSI | RWO | `pool2/k8s/media-iscsi/pvc-<uuid>` | radarr `/config` |
| `sonarr-config` | iSCSI | RWO | `pool2/k8s/media-iscsi/pvc-<uuid>` | sonarr `/config` |
| `qbittorrent-config` | iSCSI | RWO | `pool2/k8s/media-iscsi/pvc-<uuid>` | qbittorrent `/config` |

**Why iSCSI and not `truenas-nvmeof`:** NVMe-oF requires the `nvme_tcp` kernel
module on every node (see section 5); iSCSI does not, making it more robust
across node reboots. iSCSI is block storage → **RWO only**, so each app gets its
own PVC (fine — each app already used a private `subPath`).

## 1) Repo changes (GitOps source of truth)

All changes live in `kustomize/media-stack/` and are reconciled by ArgoCD. Do
NOT fix this with live `kubectl` edits — ArgoCD `selfHeal` reverts them.

- `base/_shared/iscsi-config-volumes.yaml` — new `StorageClass`
  `truenas-iscsi-media` (`datasetPath: k8s/media-iscsi`, `reclaimPolicy: Retain`,
  `fsType: ext4`) plus the three RWO config PVCs.
- `base/kustomization.yaml` — registers the new resource file.
- `base/{radarr,sonarr,qbittorrent}/deployment.yaml` — repoint `/config` from
  the shared NFS volume (`subPath`) to the per-app PVC (volume renamed `config`).
- `base/{radarr,sonarr}/deployment.yaml` — relaxed startup probes (see §6).

`datasetPath: k8s/media-iscsi` groups zvols under one parent dataset on the NAS
(matching the existing `pool2/k8s/nvmeof` convention) so they are identifiable
rather than scattered UUIDs at pool root. `reclaimPolicy: Retain` keeps the zvol
if a PVC is ever deleted.

## 2) Migration cutover procedure

Performed per app with ArgoCD auto-sync **suspended** during the window so
`selfHeal` does not fight the manual scale-down.

```bash
# 2.1 Suspend ArgoCD auto-sync for media-stack
kubectl patch application -n argocd media-stack --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'

# 2.2 Create ONLY the SC + PVCs (empty iSCSI zvols provision)
kubectl apply -n media-stack \
  -f kustomize/media-stack/base/_shared/iscsi-config-volumes.yaml
kubectl get pvc -n media-stack radarr-config sonarr-config qbittorrent-config

# 2.3 Scale the apps to 0 for a clean SQLite shutdown
kubectl scale deploy -n media-stack radarr sonarr qbittorrent --replicas=0

# 2.4 Copy config NFS -> iSCSI with a one-shot migrator pod (per app).
#     Mount old NFS subdir read-only + new PVC, then cp -a (preserves
#     1001:1001 ownership, timestamps, perms). Pin to a node that already
#     has the busybox image cached if the registry is unavailable.
```

Migrator pod shape (repeat per app, swapping names + `subPath`):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: migrate-radarr-config
  namespace: media-stack
spec:
  restartPolicy: Never
  nodeName: k8s-worker-1
  containers:
  - name: copy
    image: busybox:1.36
    command: ["/bin/sh","-c","set -e; cp -a /old/. /new/; ls -la /new"]
    volumeMounts:
    - { name: oldcfg, mountPath: /old, subPath: radarr/config, readOnly: true }
    - { name: newcfg, mountPath: /new }
  volumes:
  - name: oldcfg
    persistentVolumeClaim: { claimName: media-stack-config }
  - name: newcfg
    persistentVolumeClaim: { claimName: radarr-config }
```

```bash
# 2.5 Verify copy (DB present, ownership 1001:1001), then delete migrator pods

# 2.6 Re-enable ArgoCD auto-sync -> it rolls out the deployments bound to the
#     now-populated iSCSI PVCs
kubectl patch application -n argocd media-stack --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"enabled":true,"prune":true,"selfHeal":true}}}}'
```

The old NFS data stays untouched at `pool2/AppData/<app>/config` as a rollback.

## 3) RWO rolling-update deadlock (and how to break it)

Because iSCSI config PVCs are **RWO**, a pod must fully release its volume
before a replacement pod on a different node can attach it. During a rollout
(e.g. removing a temporary `nodeSelector`) this can deadlock:

- new ReplicaSet pod (new node) → `FailedAttachVolume: Multi-Attach ... Volume
  is already used by pod(s) <old-pod>`
- old ReplicaSet pod stays `Running` (holds the volume) because the new pod
  never becomes Ready.

Break it by scaling the **stale** ReplicaSet(s) to 0 so the volume detaches:

```bash
# find current vs stale RS per app
for app in radarr sonarr qbittorrent; do
  kubectl get rs -n media-stack -l app=$app \
    -o custom-columns=RS:.metadata.name,REV:'.metadata.annotations.deployment\.kubernetes\.io/revision',REPL:.spec.replicas,READY:.status.readyReplicas
done
# scale the OLD revision RS (the one NOT matching the deployment's current
# revision but still replicas>0) to 0:
kubectl scale rs -n media-stack <old-rs-name> --replicas=0
```

Cross-node iSCSI detach/reattach takes ~1–3 min; watch
`kubectl get volumeattachment` flip `node` to the new node with `attached=True`.

## 4) Verification

```bash
# all three Running, ArgoCD Synced+Healthy
kubectl get pods -n media-stack | grep -E 'radarr|sonarr|qbittorrent'
kubectl get application -n argocd media-stack \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'

# pods bound to the iSCSI config PVCs
kubectl get pods -n media-stack -o json | \
  jq -r '.items[].spec.volumes[]?|select(.persistentVolumeClaim.claimName|test("config"))|.persistentVolumeClaim.claimName' | sort -u

# data intact (API keys live in each app's /config/config.xml)
#   radarr:  /api/v3/movie   -> movie count
#   sonarr:  /api/v3/series  -> series count
# pipeline reachability (expect HTTP 200):
kubectl exec -n media-stack deploy/radarr -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://qbittorrent:8080/api/v2/app/version

# qBittorrent security settings survived the move
kubectl exec -n media-stack deploy/qbittorrent -c qbittorrent -- \
  grep -E 'HostHeaderValidation|CSRF|AuthSubnetWhitelist' /config/config/qBittorrent.conf
```

Post-migration confirmed: radarr ~329 movies, sonarr 16 series, radarr→qbit
HTTP 200, qBittorrent `AuthSubnetWhitelist=10.0.0.0/8`,
`HostHeaderValidation=false`, `CSRFProtection=false` all preserved.

## 5) Related incident: NVMe-oF mount + Nexus Postgres crash loop

Surfaced while the media rollout needed the private registry
(`nexus-repo`, pulled via the `registry` hostname). Chain of failures after a
node reboot:

**5a. NVMe-oF volumes fail to mount** — Nexus Postgres PVC is on
`truenas-nvmeof`. Node could not connect:

```
nvme_fabrics: no handler found for transport tcp
MountVolume.MountDevice failed ... nvme connect failed: Invalid argument
```

Cause: the **`nvme_tcp` kernel module was missing** on the node (not in
`/lib/modules/$(uname -r)`). Fix on each affected worker:

```bash
K=$(uname -r)
sudo apt-get update -qq
sudo apt-get install -y linux-modules-extra-$K   # provides nvme_tcp
sudo modprobe nvme_tcp
echo nvme_tcp | sudo tee /etc/modules-load.d/nvme_tcp.conf   # persist across reboot
```

After loading, restart the TrueNAS CSI node pod on that node if a mount is
still cached as failed:
`kubectl delete pod -n csi-truenas <truenas-csi-node-pod-on-that-node>`.

**5b. Postgres crash loop — disk full from un-archivable WAL.** Once the volume
mounted, CNPG refused to start:

```
Not enough WAL disk space, avoid starting PostgreSQL
error: no free disk space for WALs
```

Root cause: **S3 WAL archiving was failing** (`ContinuousArchiving: FAILING —
missing key REGION, inside secret s3-creds`). When archiving fails, Postgres
cannot recycle WAL segments, so `pg_wal` grew until it filled the 10Gi PGDATA
volume (actual DB data was only ~116M). Two-part fix:

1. Fix archiving creds: the kro `PGCluster` instance (`addons/nexus.yaml`,
   `--tags postgres`) populates the `s3-creds` secret (`ACCESS_KEY_ID`,
   `SECRET_ACCESS_KEY`, `REGION`) from vault vars. Re-running the playbook
   repopulated `REGION`, after which `ContinuousArchiving` reports success.
2. Give WAL headroom: bumped `spec.db.size` `10Gi → 20Gi` in `addons/nexus.yaml`
   (kro maps it to CNPG `spec.storage.size`).

Because CNPG could not drive the PVC resize while the pod was crash-looping
(`Cannot extract Pod status`), finish it manually:

```bash
kubectl patch pvc -n nexus nexus-postgres-1 --type merge \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
# PVC reports FileSystemResizePending -> restart the pod to run resize2fs:
kubectl delete pod -n nexus nexus-postgres-1
```

Result: Postgres `2/2 Running`, `ContinuousArchiving: True`, disk ~50% used,
`nexus-repo` init (`wait-for-postgres`) unblocked, registry back to a healthy
`401` on `/v2/` (was `502`).

Deeper CNPG storage layout (optional hardening): add a dedicated `walStorage`
volume so WAL pressure can never take down PGDATA again.

## 6) Operational notes & gotchas

- **iSCSI is RWO** — never assume RWX semantics. One pod per config volume;
  during rollouts ensure the old ReplicaSet scales to 0 (see §3).
- **Registry dependency** — the whole media stack pulls images through the
  private registry. If it is down, rollouts `ImagePullBackOff` **unless** the
  exact image tags are already cached on the node the pod lands on. During the
  registry outage, pods were temporarily pinned to the node that had the images
  cached (`nodeSelector: kubernetes.io/hostname=<node>`) and ArgoCD selfHeal
  paused; both were reverted once the registry recovered. This pin is a
  stopgap, not committed to Git.
- **Startup probes** on radarr/sonarr were widened (`failureThreshold: 30`,
  `timeoutSeconds: 5`): first boot after migration runs SQLite DB migration on a
  large DB and exceeded the old tight window, causing a restart loop.
- **NVMe-oF needs `nvme_tcp`** on every node after a reboot (see §5a). Prefer
  iSCSI for new block volumes unless NVMe-oF performance is specifically needed.
- **kro-managed Postgres** — `nexus-postgres` is owned by the kro `PGCluster`
  instance, NOT ArgoCD. Edit `addons/nexus.yaml` + re-run the playbook; live
  CNPG edits are reverted by kro.
