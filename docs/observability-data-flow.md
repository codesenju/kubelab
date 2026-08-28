# Observability Data Flow

This document describes how metrics and traces move from workloads through Prometheus, OBI, Alloy, Mimir, Tempo, RustFS S3, and Grafana.

## System Overview

```mermaid
flowchart LR
    subgraph Sources
        Workloads[Kubernetes workloads]
        OBI[OBI eBPF auto-instrumentation<br/>obi-system]
    end

    subgraph Collection
        Prom[Prometheus Agent<br/>kube-prometheus-stack]
        Fanout[OTel Fanout Collector<br/>otel-system]
        Alloy[Grafana Alloy<br/>grafana-system]
    end

    subgraph Storage and Query
        MGW[Mimir Gateway<br/>mimir-gateway.mimir.svc.cluster.local]
        Mimir[Mimir distributed]
        TempoGW[Tempo Gateway]
        Tempo[Tempo distributed]
        S3[(RustFS S3<br/>rustfs.rustfs.svc.cluster.local:9000)]
    end

    subgraph Presentation
        Grafana[Grafana<br/>grafana-system]
        Dashboards[Dashboards and Explore]
    end

    Workloads -->|ServiceMonitor / PodMonitor| Prom
    Prom -->|Prometheus remote_write<br/>X-Scope-OrgID: kube-prometheus-stack| MGW
    MGW --> Mimir
    Mimir -->|mimir-blocks| S3
    MGW -->|PromQL| Grafana

    OBI -->|OTLP gRPC traces :4317| Fanout
    Fanout -->|OTLP traces| Alloy
    Alloy -->|OTLP gRPC :4317| TempoGW
    TempoGW --> Tempo
    Tempo -->|tempo-traces| S3
    Alloy -->|spanmetrics connector| SpanMetrics[Trace-derived Prometheus metrics]
    SpanMetrics -->|remote_write<br/>X-Scope-OrgID: kube-prometheus-stack| MGW
    Tempo -->|trace queries| Grafana
    Grafana --> Dashboards
```

## Metrics Flow

1. Kubernetes workloads expose Prometheus-format metrics.
2. Prometheus Agent discovers targets through `ServiceMonitor` and `PodMonitor` resources supplied by the kube-prometheus-stack operator.
3. Prometheus sends samples to:

   `http://mimir-gateway.mimir.svc.cluster.local/api/v1/push`

4. Prometheus sets `X-Scope-OrgID: kube-prometheus-stack`.
5. Mimir gateway routes writes to distributors.
6. Mimir distributes samples through its ingest path, including Kafka and zone-aware ingesters.
7. Mimir compacts metric blocks and stores them in RustFS S3 bucket `mimir-blocks`.
8. Grafana queries Mimir through its Prometheus-compatible API.

Grafana datasource configuration:

```text
Name: Mimir
Type: prometheus
Access: proxy
URL: http://mimir-gateway.mimir.svc.cluster.local/prometheus
Header: X-Scope-OrgID: kube-prometheus-stack
```

## OBI Trace Flow

OBI runs eBPF-based automatic instrumentation. Current discovery targets:

- `media-stack`
- `immich`
- `homarr`
- `ddns`
- `cloudflared`

OBI exports traces to:

```text
http://otel-fanout-collector.otel-system.svc.cluster.local:4317
```

The fanout collector sends traces to Alloy. Alloy then performs two operations:

```mermaid
flowchart TB
    OBI[OBI traces] --> Fanout[OTel Fanout Collector]
    Fanout --> Alloy[Alloy OTLP receiver]
    Alloy --> Tempo[Tempo distributor]
    Tempo --> S3[(RustFS tempo-traces bucket)]
    Alloy --> Spanmetrics[spanmetrics connector]
    Spanmetrics --> Relabel[Prometheus relabel rules]
    Relabel --> Mimir[Mimir remote_write]
```

Alloy generates metrics such as:

- `traces_spanmetrics_calls_total`
- `traces_spanmetrics_duration_seconds_*`

Alloy sends those metrics to Mimir using:

```text
http://mimir-gateway.mimir.svc.cluster.local/api/v1/push
X-Scope-OrgID: kube-prometheus-stack
```

This means OBI trace-derived metrics appear in Grafana through the Mimir datasource, while original traces appear through the Tempo datasource.

## Direct OBI Metrics

OBI also exposes metrics directly:

```text
Port: 8999
Path: /metrics
Features: network, application
```

These metrics require a Prometheus scrape target for the OBI endpoint. The OBI configuration exposes the endpoint, but a matching `ServiceMonitor`, `PodMonitor`, or scrape configuration must exist before direct OBI metrics enter Prometheus and Mimir.

Direct OBI metrics and Alloy-generated spanmetrics are separate paths:

```mermaid
flowchart LR
    OBI[OBI :8999 /metrics] -->|requires scrape config| Prom[Prometheus Agent]
    Prom --> Mimir[Mimir]
    OBI -->|OTLP traces| Fanout[OTel Fanout]
    Fanout --> Alloy[Alloy spanmetrics]
    Alloy --> Mimir
```

## Trace Queries and Service Map

Grafana has two relevant datasources:

```text
Mimir: uid=mimir
Tempo: uid=tempo
```

The Tempo datasource points to:

```text
http://tempo-gateway.grafana-system.svc.cluster.local
```

Tempo's service-map configuration references Mimir datasource UID `mimir`. Grafana therefore uses Tempo for trace data and Mimir for service-map metrics derived from traces.

### Confirmed Service Graph

Grafana Explore successfully renders service-graph data from the Tempo datasource. The current OBI-generated graph includes relationships such as:

```mermaid
flowchart LR
    User[user] --> Immich[immich]
    User --> Homarr[homarr]
    User --> Cloudflared[cloudflared]
    Immich --> Unknown[unknown]
```

The graph confirms this path is working:

```text
OBI traces
  -> OTel Fanout Collector
  -> Alloy servicegraph connector
  -> Mimir remote_write
  -> Grafana Mimir datasource
  -> Tempo Service Graph view
```

The `unknown` node means OBI observed a downstream relationship without a usable destination service name in the span attributes. This is an instrumentation metadata limitation, not a Grafana, Mimir, or Tempo availability failure. Service names become more precise when applications provide standard OpenTelemetry resource attributes such as `service.name` and peer service metadata.

The Service Graph view also displays RED metrics generated by Alloy, including request rate, error rate, and duration. These metrics are stored in Mimir under tenant `kube-prometheus-stack`.

### Enable Service Graph in Grafana

Grafana service graphs require three pieces:

1. A trace pipeline that generates service-graph metrics.
2. A Prometheus-compatible datasource containing those metrics.
3. A Tempo datasource linked to that metrics datasource.

This cluster uses Alloy for service-graph generation. Its OTLP receiver sends each trace to the `servicegraph` connector, which forwards generated metrics to Mimir:

```hcl
otelcol.receiver.otlp "default" {
  output {
    traces = [
      otelcol.connector.servicegraph.default.input,
      otelcol.processor.batch.default.input,
    ]
  }
}

otelcol.connector.servicegraph "default" {
  dimensions = ["http.method", "http.target"]
  output {
    metrics = [otelcol.exporter.prometheus.default.input]
  }
}
```

The Alloy remote-write endpoint must use same Mimir tenant as Grafana:

```hcl
prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir-gateway.mimir.svc.cluster.local/api/v1/push"
    headers = {
      "X-Scope-OrgID" = "kube-prometheus-stack",
    }
  }
}
```

The Grafana datasources are linked through the Tempo datasource configuration:

```yaml
- name: Mimir
  type: prometheus
  uid: mimir
  url: http://mimir-gateway.mimir.svc.cluster.local/prometheus
  jsonData:
    httpHeaderName1: X-Scope-OrgID
  secureJsonData:
    httpHeaderValue1: kube-prometheus-stack

- name: Tempo
  type: tempo
  uid: tempo
  url: http://tempo-gateway.grafana-system.svc.cluster.local
  jsonData:
    serviceMap:
      datasourceUid: mimir
```

After deployment, open **Grafana -> Explore -> Tempo -> Service Graph** and select a time range containing traces. Service graph metrics can be checked directly in Mimir with:

```promql
traces_service_graph_request_total
```

The Service Graph view table additionally uses:

```promql
traces_spanmetrics_calls_total
traces_spanmetrics_duration_seconds_bucket
```

If the graph is empty, verify that traces contain client/server relationships, Alloy is ready, the Mimir tenant header matches, and the linked datasource UID is `mimir`.

## Object Storage

Mimir stores metric blocks in RustFS through the internal endpoint:

```text
rustfs.rustfs.svc.cluster.local:9000
```

Tempo stores trace blocks in the `tempo-traces` bucket using the same internal RustFS service path.

Configured Mimir metric retention:

```yaml
limits:
  compactor_blocks_retention_period: 30d
```

The Prometheus Agent's local storage is temporary `emptyDir` storage with a configured `10d` retention value. It is a buffering layer, not durable long-term storage. Durable retention is controlled by Mimir's compactor and S3 blocks.

## Dependency Graph

```mermaid
flowchart TD
    K8s[Kubernetes API] --> Operator[Prometheus Operator]
    Operator --> Prom[Prometheus Agent]
    Prom --> MGW[Mimir Gateway]
    MGW --> Dist[Mimir Distributor]
    Dist --> Kafka[Mimir Kafka ingest]
    Kafka --> Ing[Mimir zone-aware ingesters]
    Ing --> Comp[Mimir Compactor]
    Comp --> S3[(RustFS S3)]
    MGW --> Query[Mimir Query Frontend / Querier]
    Query --> Grafana[Grafana]

    OBI[OBI] --> Fanout[OTel Fanout Collector]
    Fanout --> Alloy[Alloy]
    Alloy --> TempoDist[Tempo Distributor]
    TempoDist --> TempoIng[Tempo Ingesters]
    TempoIng --> TempoComp[Tempo Compactor]
    TempoComp --> S3T[(RustFS tempo-traces)]
    Tempo --> Grafana

    Argo[Argo CD] -.-> Prom
    Argo -.-> MGW
    Argo -.-> Alloy
    Argo -.-> Tempo
```

## Verification Commands

Check workload health:

```bash
kubectl get pods -n kube-prometheus-stack
kubectl get pods -n grafana-system
kubectl get pods -n mimir
```

Check GitOps health:

```bash
kubectl get application -n argocd kube-prometheus-stack grafana alloy tempo mimir
```

Check Mimir query access with correct tenant:

```bash
kubectl run mimir-check -n grafana-system --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 -- \
  curl -sS -H 'X-Scope-OrgID: kube-prometheus-stack' \
  'http://mimir-gateway.mimir.svc.cluster.local/prometheus/api/v1/query?query=up'
```

Expected result is HTTP `200` with a non-empty vector when Prometheus is scraping targets.

Check trace-derived metrics:

```text
traces_spanmetrics_calls_total
```

Check Tempo trace ingestion through Grafana Explore or Tempo's trace search. Check service-map metrics through the Mimir datasource.

## Known Failure Modes

- Missing `X-Scope-OrgID` sends Alloy samples to the `anonymous` tenant while Grafana queries `kube-prometheus-stack`.
- External S3 ingress failures can prevent Tempo or Mimir components from starting. Internal RustFS service DNS avoids that ingress dependency.
- Prometheus Agent memory pressure can cause `OOMKilled`, readiness failures, out-of-order sample drops, and missing data in Mimir.
- OBI direct metrics remain absent unless Prometheus scrapes OBI port `8999`.
