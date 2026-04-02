# Nexus Postgres NFS Runbook

This runbook prevents and recovers `applyFSGroup failed` / `permission denied` mount errors for the Nexus Postgres PVC on the NAS NFS share.

## Scope

- Kubernetes namespace: `nexus`
- CNPG cluster: `nexus-postgres`
- NFS server: `192.168.0.16`
- Share path: `/mnt/pool2/k8s/nfs-postgres`

## 1) One-time NAS hardening (recommended)

Run on the NAS to make new PVC folders group-friendly by default.

```bash
ssh -i "$HOME/codesenju/kubelab.pem" root@192.168.0.16 '
set -e
install -d -m 2777 /mnt/pool2/k8s/nfs-postgres
chgrp docker /mnt/pool2/k8s/nfs-postgres
setfacl -m d:u::rwx,d:g::rwx,d:o::rwx /mnt/pool2/k8s/nfs-postgres
setfacl -m u::rwx,g::rwx,o::rwx /mnt/pool2/k8s/nfs-postgres
getfacl /mnt/pool2/k8s/nfs-postgres
'
```

Notes:

- `2777` keeps the setgid bit so child dirs inherit the parent group.
- Default ACLs make newly provisioned PVC subdirs writable/traversable.

## 2) Fast recovery for an existing broken PVC

When CNPG pod fails with `applyFSGroup failed` on an existing volume:

```bash
ssh -i "$HOME/codesenju/kubelab.pem" root@192.168.0.16 '
set -e
PVC_DIR=/mnt/pool2/k8s/nfs-postgres/pvc-87405123-4c08-4821-8b05-bbe9456bd868
chmod 0777 "$PVC_DIR"
if [ -d "$PVC_DIR/pgdata" ]; then chmod -R 0777 "$PVC_DIR/pgdata"; fi
ls -ld "$PVC_DIR" "$PVC_DIR/pgdata" || true
'

kubectl -n nexus delete pod nexus-postgres-1
kubectl -n nexus wait --for=condition=ready pod/nexus-postgres-1 --timeout=300s
kubectl -n nexus rollout restart deploy/nexus-repo
kubectl -n nexus rollout status deploy/nexus-repo --timeout=300s
```

## 3) Verification

```bash
kubectl -n nexus get pods -o wide
kubectl -n nexus get svc nexus-postgres-rw -o wide
kubectl -n nexus logs deploy/nexus-repo --tail=120
```

Expected:

- `nexus-postgres-1` is `1/1 Running`
- `nexus-repo` is `1/1 Running`
- Nexus log contains `Started Sonatype Nexus COMMUNITY`

## 4) Preventive checks

```bash
kubectl -n nexus get events --sort-by=.lastTimestamp | grep -E 'FailedMount|applyFSGroup|permission denied'
kubectl -n nexus get pvc,pv | grep nexus-postgres
```

If events recur after node reschedules, re-check NFS export and ACL policy for `/mnt/pool2/k8s/nfs-postgres`.
