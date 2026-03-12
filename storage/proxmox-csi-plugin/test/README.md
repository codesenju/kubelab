### Create Snapshot from PVC
```bash
export SNAPSHOT_NAME="busybox-pvc-snapshot-$(date +%Y-%m-%d-%Hh%M)"
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
### Create PVC from Snapshot
```bash
export SNAPSHOT_NAME="busybox-pvc-snapshot-2026-03-12-07h57"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: busybox-restore-$(date +%Y-%m-%d-%Hh%M)
  namespace: test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: proxmox-csi
  resources:
    requests:
      storage: 1Gi
  dataSource:
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
    name: $SNAPSHOT_NAME
EOF
```
### Create POD from restored PVC
```bash
export RESTORE_PVC="busybox-restore-2026-03-12-11h40"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-restore-pod
  namespace: test
spec:
  containers:
    - name: busybox
      image: busybox:latest
      command:
        - "/bin/sh"
        - "-c"
        - "while true; do echo running && sleep 4; done"
      volumeMounts:
        - name: volume
          mountPath: /mnt
  volumes:
    - name: volume
      persistentVolumeClaim:
        claimName: $RESTORE_PVC
  restartPolicy: Never
EOF
```