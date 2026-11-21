# Storage

## Proxmox local storage

Each node has a `local` directory store and an `local-lvm` thin pool on its NVMe disk. See [Proxmox nodes](proxmox-nodes.md) for sizes.

## Kubernetes storage classes

Snapshot from 2026-11-21. The TrueNAS classes use the TrueNAS CSI driver.

| Class | Provisioner | Namespaces with volumes |
|---|---|---|
| nfs-csi | nfs.csi.k8s.io | crowdsec, mimir, signoz, zero-trust |
| nfs-csi-postgres | nfs.csi.k8s.io | none |
| truenas-iscsi | csi.truenas.io | backstage, coder, hindsight, immich, postiz, sbench, signoz |
| truenas-iscsi-media | csi.truenas.io | media-stack, omniroute |
| truenas-nfs | csi.truenas.io | none |
| truenas-nfs-encrypted | csi.truenas.io | none |
| truenas-nfs-postgres | csi.truenas.io | none |
| truenas-nfs-zstd | csi.truenas.io | none |
| truenas-nvmeof | csi.truenas.io | crowdsec, nexus, signoz |

Volumes with no class are usually static volumes or `hostPath`-style claims.

## TrueNAS

TrueNAS runs as a VM on kubelab-1 and serves NFS, iSCSI and NVMe-oF to the cluster. A read-only account exists for catalog use. The catalog does not read TrueNAS yet.
