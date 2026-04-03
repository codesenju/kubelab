# Nexus Postgres NFS Runbook

This runbook prevents and recovers `applyFSGroup failed` / `permission denied` mount errors for the Nexus Postgres PVC on the NAS NFS share, and covers backup recovery when WAL archiving gets stuck.

## Scope

- Kubernetes namespace: `nexus`
- CNPG cluster: `nexus-postgres`
- NFS server: `192.168.0.16`
- Share path: `/mnt/pool2/k8s/nfs-postgres`

## 1) One-time NAS hardening (recommended)

Run on the NAS to make new PVC folders writable by default and ensure Kubernetes fsGroup/chown logic can work over NFS.

```bash
ssh -i "$HOME/codesenju/kubelab.pem" root@192.168.0.16 '
set -e
install -d -m 2777 /mnt/pool2/k8s/nfs-postgres
chown nobody:nogroup /mnt/pool2/k8s/nfs-postgres
setfacl -m d:u:postgres:rwx,d:g:nogroup:rwx,d:o::rwx /mnt/pool2/k8s/nfs-postgres
setfacl -m u::rwx,g::rwx,o::rwx /mnt/pool2/k8s/nfs-postgres
getfacl /mnt/pool2/k8s/nfs-postgres
'
```

Also verify NAS exports include `no_root_squash,no_subtree_check` for this share:

```bash
ssh -i "$HOME/codesenju/kubelab.pem" root@192.168.0.16 '
grep -n "/mnt/pool2/k8s/nfs-postgres" /etc/exports
exportfs -v | grep -A1 "/mnt/pool2/k8s/nfs-postgres"
'
```

Notes:

- `2777` keeps the setgid bit so child dirs inherit the parent group.
- Default ACLs make newly provisioned PVC subdirs writable/traversable.
- `no_root_squash` avoids kubelet/CSI permission rewrite failures during mount and fsGroup application.

## 2) StorageClass mount options hardening

Use safer NFS mount options for Postgres workloads:

```yaml
mountOptions:
  - nfsvers=4.1
  - noatime
  - hard
  - timeo=600
  - retrans=2
```

Quick check:

```bash
kubectl get storageclass nfs-csi-postgres -o jsonpath='{.mountOptions[*]}{"\n"}'
```

## 3) Fast recovery for an existing broken PVC

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

## 4) Verification

```bash
kubectl -n nexus get pods -o wide
kubectl -n nexus get svc nexus-postgres-rw -o wide
kubectl -n nexus logs deploy/nexus-repo --tail=120
```

Expected:

- `nexus-postgres-1` is `1/1 Running`
- `nexus-repo` is `1/1 Running`
- Nexus log contains `Started Sonatype Nexus COMMUNITY`

## 5) Backup troubleshooting (WAL archiving + connection saturation)

Symptoms:

- Backup CR phase stuck in `running`/`pending` or ends in `walArchivingFailing`.
- Postgres logs show archive failures and repeated local connection failures (`too many clients already`).

Root cause chain seen in production:

1. NFS permission instability causes pod restarts / unhealthy periods.
2. WAL archiving and backup reconciliation loops retry repeatedly.
3. CNPG control checks open repeated local connections, eventually hitting connection limits.

Actions:

```bash
# 1) Ensure pod is healthy and mount errors are gone first
kubectl -n nexus get pod nexus-postgres-1
kubectl -n nexus get events --sort-by=.lastTimestamp | grep -E 'FailedMount|applyFSGroup|permission denied'

# 2) Remove failed/running stale backups before retry
kubectl -n nexus get backups.postgresql.cnpg.io
kubectl -n nexus delete backup.postgresql.cnpg.io <stale-backup-name>

# 3) Trigger manual backup
cat <<'EOF' | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: nexus-postgres-manual-<timestamp>
  namespace: nexus
spec:
  cluster:
    name: nexus-postgres
  method: barmanObjectStore
  target: primary
EOF

kubectl -n nexus wait \
  --for=jsonpath='{.status.phase}'=completed \
  backup.postgresql.cnpg.io/nexus-postgres-manual-<timestamp> \
  --timeout=300s
```

If you recreated the cluster, make sure the S3 destination is clean for the server name before first backup.

## 6) Preventive checks

```bash
kubectl -n nexus get events --sort-by=.lastTimestamp | grep -E 'FailedMount|applyFSGroup|permission denied'
kubectl -n nexus get pvc,pv | grep nexus-postgres
```

If events recur after node reschedules, re-check NFS export and ACL policy for `/mnt/pool2/k8s/nfs-postgres`.
