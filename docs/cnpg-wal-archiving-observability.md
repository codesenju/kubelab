# CloudNativePG WAL Archiving Observability

End-to-end guide for monitoring CloudNativePG (CNPG) PostgreSQL clusters in
SigNoz: scraping the native `cnpg_*` metrics, shipping them cross-cluster to
SigNoz, building the dashboard, and wiring the WAL-archiving alerts.

This exists because of a real incident: three CNPG clusters silently stopped
backing up for ~30 days. The backups showed `started` in `kubectl get backup`
but never completed, because a rotated RustFS S3 secret key made every WAL
archive upload fail with `SignatureDoesNotMatch`. No one noticed, because
nothing was watching WAL archiving. This setup makes that failure mode loud.

## Table of Contents

- [Architecture](#architecture)
- [Why WAL archiving is the signal that matters](#why-wal-archiving-is-the-signal-that-matters)
- [The metrics](#the-metrics)
- [Repo layout](#repo-layout)
- [Component 1 — the metrics collector (kustomize)](#component-1--the-metrics-collector-kustomize)
- [Component 2 — the Ansible addon (ArgoCD Application)](#component-2--the-ansible-addon-argocd-application)
- [Deploy end to end](#deploy-end-to-end)
- [The dashboard](#the-dashboard)
- [The alerts](#the-alerts)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Architecture

SigNoz runs on the **homelab** cluster. The CNPG clusters being monitored run
on the **Contabo** production cluster. A dedicated OpenTelemetry Collector on
Contabo scrapes every CNPG pod and ships the metrics to SigNoz over Tailscale.

```
Contabo cluster (production)                        Homelab cluster
┌─────────────────────────────────────┐            ┌────────────────────────┐
│  CNPG pods (all namespaces)          │            │  SigNoz                │
│  ekonnecta / iysynergy / n8n /       │            │  ┌──────────────────┐  │
│  zero-trust  …                       │            │  │ signoz-otel-     │  │
│    :9187/metrics  (cnpg_* metrics)   │            │  │ collector :4318  │  │
│          ▲                           │            │  └────────▲─────────┘  │
│          │ scrape (prometheus recv)  │            │           │ ClickHouse │
│  ┌───────┴───────────────────────┐   │  OTLP/HTTP │           │            │
│  │ cnpg-metrics-collector        │───┼────────────┼───────────┘            │
│  │ (otel-collector-contrib)      │   │  over       │  Dashboard + Alerts    │
│  └───────────────────────────────┘   │  Tailscale  │                        │
└─────────────────────────────────────┘  (HTTPS 443) └────────────────────────┘
        signoz-otel-collector.local.domain.com
```

Key points:

- The collector lives in the `signoz` namespace on Contabo and uses the
  Prometheus receiver's Kubernetes pod discovery to find **all** CNPG instance
  pods (`cnpg.io/podRole=instance`) across every namespace — one collector
  covers every cluster, no per-namespace config.
- CNPG exposes metrics on container port `9187` (`metrics`). The operator does
  **not** create a PodMonitor by default (`spec.monitoring.enablePodMonitor`
  is false), and this cluster has no Prometheus Operator, so a standalone
  collector with pod discovery is the right fit.
- Export is **OTLP/HTTP over HTTPS** to the Tailscale FQDN, not the internal
  service DNS. `signoz-otel-collector.signoz.svc.cluster.local` only resolves
  inside the homelab cluster; from Contabo the only reachable path is the
  Tailscale-advertised hostname on port 443 (ports 4317/4318 are not exposed
  cross-cluster).

## Why WAL archiving is the signal that matters

A CNPG backup is a base backup plus a continuous stream of archived WAL
segments. The base backup can succeed while WAL archiving is broken, and the
`Backup` object can sit in `started` indefinitely without ever going to
`failed`. So "did the nightly `Backup` object complete?" is **not** a reliable
health signal — WAL archiving is.

PostgreSQL tracks archiving natively in `pg_stat_archiver`, and CNPG exports it.
The question that actually catches silent data loss is:

> How long has it been since this cluster last successfully archived a WAL
> segment, and is it currently recording archive failures?

## The metrics

All prefixed `cnpg_` and scraped from `:9187/metrics`. The archiving-specific
ones (from `pg_stat_archiver`) are the alert signals:

| Metric | Type | Meaning |
|---|---|---|
| `cnpg_pg_stat_archiver_seconds_since_last_archival` | gauge | Seconds since the last **successful** WAL archive. Primary staleness signal. |
| `cnpg_pg_stat_archiver_seconds_since_last_failure` | gauge | Seconds since the last **failed** archive attempt. |
| `cnpg_pg_stat_archiver_failed_count` | counter | Cumulative failed archive attempts. Rising = active failures. |
| `cnpg_pg_stat_archiver_archived_count` | counter | Cumulative successful archives. |
| `cnpg_collector_pg_wal_archive_status` | gauge | WAL segments `ready` (pending) vs `done` in `archive_status/`. `ready` growing = backlog. |

The collector relabels each series with `cnpg_cluster`, `k8s_namespace_name`,
`k8s_pod_name`, and `cnpg_instance_role` so dashboards and alerts can scope
per cluster.

> **Note on quiet databases.** `pg_stat_archiver` only timestamps an archival
> when a 16 MB WAL segment is actually shipped. A low-traffic database may not
> fill a segment for an hour or more, so `seconds_since_last_archival` reading
> 40-70 minutes on a quiet cluster is **healthy**, not a stall. The alert
> threshold (3h) is deliberately set well above normal WAL cadence to avoid
> false positives while still catching a real outage (which lasted 30 days).

## Repo layout

```
kubelab/
├── addons/
│   └── cnpg-metrics.yaml                        # Ansible playbook → ArgoCD Application
└── kustomize/
    └── cnpg-metrics/
        ├── base/
        │   ├── kustomization.yaml
        │   ├── rbac.yaml                         # SA + ClusterRole/Binding (cross-ns pod discovery)
        │   ├── configmap.yaml                    # OTel Collector config (prometheus → OTLP/HTTP)
        │   └── deployment.yaml                   # otel-collector-contrib Deployment
        └── overlays/
            └── prod/
                └── kustomization.yaml            # namespace: signoz → ../../base
```

This mirrors the existing `kustomize/otel-collector/` + `addons/otel-collector.yaml`
pattern: a kustomize base/overlay for the manifests, and an Ansible playbook
that creates an ArgoCD `Application` pointing at the overlay.

## Component 1 — the metrics collector (kustomize)

### `base/rbac.yaml`

The Prometheus receiver's Kubernetes service discovery needs cluster-wide read
access to pods/endpoints to find CNPG instances in every namespace. A
`ServiceAccount` in the `signoz` namespace is bound to a `ClusterRole` granting
`get/list/watch` on pods, endpoints, services, nodes, and endpointslices, plus
`/metrics`.

### `base/configmap.yaml`

The OTel Collector config. The important parts:

```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: cnpg
          scrape_interval: 30s
          kubernetes_sd_configs:
            - role: pod
          relabel_configs:
            # keep only CNPG instance pods
            - source_labels: [__meta_kubernetes_pod_label_cnpg_io_podRole]
              action: keep
              regex: instance
            # scrape only the metrics port
            - source_labels: [__meta_kubernetes_pod_container_port_name]
              action: keep
              regex: metrics
            # relabel for per-cluster scoping
            - source_labels: [__meta_kubernetes_namespace]
              target_label: k8s_namespace_name
            - source_labels: [__meta_kubernetes_pod_label_cnpg_io_cluster]
              target_label: cnpg_cluster
            - source_labels: [__meta_kubernetes_pod_name]
              target_label: k8s_pod_name
            - source_labels: [__meta_kubernetes_pod_label_cnpg_io_instanceRole]
              target_label: cnpg_instance_role

exporters:
  # cross-cluster: OTLP/HTTP over HTTPS via Tailscale, NOT internal svc DNS
  otlphttp/signoz:
    endpoint: https://signoz-otel-collector.local.domain.com
    sending_queue: { enabled: true, num_consumers: 10, queue_size: 1000 }
    retry_on_failure: { enabled: true, initial_interval: 5s, max_interval: 30s, max_elapsed_time: 300s }

service:
  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [resource/environment, batch]
      exporters: [otlphttp/signoz, debug]
```

> If you deploy this on the **same** cluster as SigNoz, switch the exporter
> back to gRPC on the internal service:
> `otlp/signoz: { endpoint: signoz-otel-collector.signoz.svc.cluster.local:4317, tls: { insecure: true } }`
> and reference `otlp/signoz` in the pipeline instead.

### `base/deployment.yaml`

A single-replica `otel/opentelemetry-collector-contrib` Deployment mounting the
ConfigMap and running under the `cnpg-metrics-collector` ServiceAccount. The
`contrib` image is required for the Prometheus receiver + k8s SD.

## Component 2 — the Ansible addon (ArgoCD Application)

`addons/cnpg-metrics.yaml` creates an ArgoCD `Application` that syncs
`kustomize/cnpg-metrics/overlays/prod` into the `signoz` namespace with
`CreateNamespace=true`, `selfHeal`, and `prune`:

```yaml
- hosts: k8s-control-plane-1
  gather_facts: no
  become: no
  vars:
    target_namespace: signoz
  tasks:
    - name: Deploy CNPG metrics collector
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: cnpg-metrics
            namespace: argocd
            finalizers: [resources-finalizer.argocd.argoproj.io]
          spec:
            project: default
            source:
              repoURL: https://github.com/codesenju/kubelab.git
              path: kustomize/cnpg-metrics/overlays/prod
              targetRevision: main
            destination:
              server: https://kubernetes.default.svc
              namespace: '{{ target_namespace }}'
            syncPolicy:
              automated: { prune: true, selfHeal: true }
              syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

Because `selfHeal` tracks git `main`, any change to the collector config must
be committed and pushed, not just `kubectl apply`-ed — ArgoCD will otherwise
revert a manual edit on its next sync.

## Deploy end to end

Prerequisites: the CNPG operator (`addons/cnpg.yaml`) and SigNoz
(`addons/signoz.yaml`) are already deployed, and the Contabo cluster has
Tailscale connectivity to the homelab SigNoz OTLP endpoint.

```bash
cd ansible

# Contabo production inventory
export INVENTORY=inventories/contabo/hosts.ini

# 1. Deploy the collector (creates the ArgoCD Application)
ansible-playbook -i "$INVENTORY" ../addons/cnpg-metrics.yaml --vault-password-file ~/vault-password.txt

# 2. Confirm ArgoCD synced it
kubectl -n argocd get application cnpg-metrics
# Expected: SYNC=Synced, HEALTH=Healthy

# 3. Confirm the collector pod is scraping
kubectl -n signoz get pods -l app=cnpg-metrics-collector
kubectl -n signoz logs deploy/cnpg-metrics-collector --tail=20
# Expected: "Metrics ... data points: N" lines, NO "no such host" export errors
```

The dashboard and alerts are created in SigNoz via the SigNoz MCP server /
skills (see below), not by the playbook. They are data-plane objects in
SigNoz's own store, independent of the collector.

## The dashboard

Created from the curated **CloudNativePG** template bundled with SigNoz, which
reads exactly the `cnpg_*` metrics this collector ships.

- **Name:** CloudNativePG
- **Sections (8):** Cluster Health · Connections & Backends · Throughput ·
  Cache & Block I/O · Replication · WAL & Archiving · Checkpoints ·
  Storage & Collector
- **Variables:** `pod`, `datname` (database) — dynamic, populated from live
  labels.
- **41 panels** (29 time-series + 12 stat).

Create it with the `signoz-creating-dashboards` skill, or import directly via
the MCP tool:

```
signoz_import_dashboard(path="cloudnative-pg/cloudnative-pg-dashboard.json")
```

The **WAL & Archiving** section is the one that would have surfaced the
original incident.

## The alerts

Two threshold rules, both scoped per cluster (grouped by `cnpg_cluster` +
`k8s_namespace_name`) and routed to the **Jazziro** email notification channel.
Created with the `signoz-creating-alerts` skill.

### Alert 1 — CNPG WAL archiving stalled (critical)

- **Metric:** `cnpg_pg_stat_archiver_seconds_since_last_archival`
  (`timeAggregation: avg`, `spaceAggregation: max`)
- **Condition:** `> 10800` (3 hours), `matchType: at_least_once`
- **Window / frequency:** 5m / 1m
- **Fires when:** a cluster has not successfully archived a WAL segment in over
  3 hours — the exact condition behind the 30-day silent gap.

### Alert 2 — CNPG WAL archiving failures (warning)

- **Metric:** `cnpg_pg_stat_archiver_failed_count`
  (`timeAggregation: increase`, `spaceAggregation: max`)
- **Condition:** `> 0` over a 10m window, `matchType: at_least_once`
- **Window / frequency:** 10m / 1m
- **Fires when:** a cluster records any failed archive attempt — a fast signal
  that catches active failures within minutes, independent of WAL cadence (so
  it is not fooled by quiet databases).

Together: Alert 2 pages quickly when archiving *starts* failing; Alert 1 is the
backstop that catches a sustained stall even if failures aren't being counted.

Both route to channel `Jazziro` (UUID `01a082fc-55f2-7a50-8793-0bb939498c62`,
email → `me@domain.com`), re-notify every 4h while firing.

> SigNoz alert rules and dashboards live in SigNoz's own store (ClickHouse +
> SQLite), **not** in this git repo. To reproduce them declaratively, use the
> SigNoz MCP skills (`signoz-creating-dashboards`, `signoz-creating-alerts`) or
> the SigNoz Terraform provider. The git-managed part is the collector only.

## Verification

```bash
# 1. Collector scraping (Contabo)
kubectl -n signoz logs deploy/cnpg-metrics-collector --tail=30 | grep -c "no such host"
# Expected: 0  (any non-zero = export broken; check the Tailscale FQDN / SigNoz)

# 2. Metrics present in SigNoz (homelab) — via MCP
#    signoz_list_metrics searchText="cnpg"  → should list cnpg_pg_stat_archiver_*

# 3. WAL archive status has zero backlog
#    cnpg_collector_pg_wal_archive_status{value="ready"} should be 0

# 4. Ground-truth check straight from Postgres (any cluster)
kubectl -n <ns> exec <cluster>-1 -c postgres -- psql -U postgres -tAc \
  "select archived_count, failed_count, last_archived_time, last_failed_time from pg_stat_archiver;"
# Healthy: last_archived_time more recent than last_failed_time; failed_count not climbing
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Collector logs `no such host` for `signoz-otel-collector...` | Export target is internal svc DNS, unreachable cross-cluster, or SigNoz down | Confirm the exporter uses the Tailscale FQDN `https://signoz-otel-collector.local.domain.com`; check Tailscale is up on both ends |
| `cnpg_*` metrics missing in SigNoz | Collector not discovering pods, or RBAC denied | `kubectl -n signoz logs deploy/cnpg-metrics-collector` — look for discovery/RBAC errors; confirm the ClusterRoleBinding subject namespace is `signoz` |
| Backups stuck in `started`, WAL archive failing with `SignatureDoesNotMatch` | Stale/rotated S3 (RustFS) secret key in the namespace `s3-creds` secret | Copy the correct `SECRET_ACCESS_KEY` from a working namespace into the failing one; WAL archiving recovers within seconds |
| Alert 1 fires on a quiet database | 3h threshold too tight for a very low-traffic cluster | Raise the threshold, or set `archive_timeout` on the cluster to force periodic WAL rotation |
| Manual config edit keeps reverting | ArgoCD `selfHeal` tracks git `main` | Commit and push the change instead of `kubectl apply` |
| `kubectl delete backup` says `backups.longhorn.io not found` | Short name `backup` resolves to the Longhorn CRD first | Use the fully-qualified `backup.postgresql.cnpg.io` |

## Related

- [Observability Data Flow](observability-data-flow.md)
- [SigNoz addon](../addons/signoz.yaml) · [CNPG addon](../addons/cnpg.yaml)
- [Collector manifests](../kustomize/cnpg-metrics/)
