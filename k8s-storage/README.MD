# Kubernetes Storage Configuration

This guide explains how to configure and use storage in the Kubelab Kubernetes cluster.

## Storage Classes

The cluster is configured with the following storage classes:

1. **nfs-client** - Default storage class using TrueNAS NFS
2. **local-path** - Local storage on nodes

## TrueNAS NFS Configuration

### Server Configuration

Configure your TrueNAS server with these settings for optimal compatibility:

- **Share Path**: `/mnt/pool1/k8s/nfs`
- **Permissions**:
  - Enabled: ✓
  - Network: 192.168.0.0/24 (adjust to your subnet)
  - Maproot User: root
  - Maproot Group: wheel (for macOS compatibility)
  - Security: sys
  - NFSv4: ❌ (disabled for better macOS compatibility)

### Mounting NFS Shares

#### macOS

```bash
mount -t nfs -o vers=3,resvport,noatime,nolocks,locallocks 192.168.0.15:/mnt/pool1/k8s/nfs ~/nfs-test
```

#### Ubuntu/Linux

```bash
sudo mount 192.168.0.15:/mnt/pool1/k8s/nfs nfs-test/
```

#### Windows

Enable NFS client:

```powershell
dism /online /enable-feature /featurename:ServicesForNFS-ClientOnly /all
```

Mount as a drive:

```powershell
mount -o nolock -o mtype=hard 192.168.0.15:/mnt/pool1/k8s/nfs Z:
```

Or as a persistent drive:

```powershell
New-PSDrive -Name "Z" -PSProvider FileSystem -Root "\\192.168.0.15\mnt\pool1\k8s\nfs" -Persist
```

## Using Storage in Kubernetes

### Creating a PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
  namespace: my-namespace
spec:
  accessModes:
    - ReadWriteMany  # NFS supports multiple readers and writers
  resources:
    requests:
      storage: 10Gi
  # storageClassName: nfs-client  # Optional as it's the default
```

### Enabling Volume Expansion

To enable volume expansion for existing storage classes:

```bash
ansible-playbook main.yaml --tags adhoc,enable_volume_expansion
```

## Troubleshooting

### Common Issues

1. **PVC stuck in Pending state**:
   - Check if the NFS server is accessible
   - Verify that the storage class exists
   - Check events with `kubectl describe pvc <name>`

2. **Permission issues**:
   - Ensure proper ownership and permissions on the NFS share
   - Check if the pod security context is compatible with NFS permissions

3. **Performance issues**:
   - Consider adjusting NFS mount options
   - For write-heavy workloads, consider using local storage instead
