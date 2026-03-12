```bash
SNAPSHOT_NAME="busybox-pvc-snapshot-$(date +%Y-%m-%d-%Hh%M)"
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: test
spec:
  volumeSnapshotClassName: proxmox-csi-snapshot
  source:
    persistentVolumeClaimName: busybox-pvc
EOF
```
