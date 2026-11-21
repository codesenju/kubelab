# Media stack

Deployed from `kustomize/media-stack` as one Argo CD application in the `media-stack` namespace. Workloads from the cluster on 2026-11-21.

| Workload | Image | Replicas |
|---|---|---|
| bazarr | bazarr:nightly-v1.6.3 | 1 |
| flaresolverr | flaresolverr:v3.4.6 | 1 |
| jellyfin | jellyfin:12 | 1 |
| prowlarr | prowlarr:2.6.5-nightly | 1 |
| qbittorrent | gluetun:v3.41.3 | 1 |
| radarr | radarr:7.0.0-nightly | 1 |
| seerr | seerr:v3.5.2 | 1 |
| sonarr | sonarr:4.0.20 | 1 |
| tdarr | tdarr:2.70.01 | 1 |
| tdarr-worker | tdarr_node:2.70.01 | 2 |

## Volumes

| Claim | Class | Size |
|---|---|---|
| media-data | none | 250Gi |
| media-stack-config | none | 20Gi |
| qbittorrent-config | truenas-iscsi-media | 2Gi |
| radarr-config | truenas-iscsi-media | 5Gi |
| radarr-config-forensic | truenas-iscsi-media | 5Gi |
| radarr-config-recovered-20261112 | truenas-iscsi-media | 5Gi |
| sonarr-config | truenas-iscsi-media | 5Gi |
| sonarr-config-forensic | truenas-iscsi-media | 5Gi |
| sonarr-config-recovered-20261112 | truenas-iscsi-media | 5Gi |
| sonarr-logdb-repair-work | truenas-iscsi-media | 5Gi |

Recovery and forensic copies of the Sonarr and Radarr config volumes may still exist next to the live ones. Check before deleting any claim.
