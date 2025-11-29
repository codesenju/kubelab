# Tempo Service Graph Issue - Root Cause and Fix

## Investigation Summary

**Date:** 2025-11-29  
**Issue:** Tempo service graph showing "No data" despite correct datasource configuration

## Root Cause Analysis

### 1. Metrics Verification (Mimir)
Queried Mimir for required span metrics:
- `traces_spanmetrics_calls_total` - **NOT FOUND**
- `traces_service_graph_request_total` - **NOT FOUND**
- `traces_spanmetrics_duration_seconds_bucket` - **NOT FOUND**

**Result:** No span metrics exist in Mimir

### 2. Tempo Configuration Check
Examined Tempo ConfigMap (`tempo-config` in `grafana-system` namespace):
- **Missing:** `metrics_generator` configuration section
- **Missing:** Metrics generator processor configuration
- **Missing:** Remote write configuration to Mimir

### 3. Tempo Deployment Check
Checked running Tempo pods:
```
tempo-compactor
tempo-distributor
tempo-gateway
tempo-ingester (0,1,2)
tempo-memcached
tempo-querier
tempo-query-frontend
```

**Missing:** `tempo-metrics-generator` pod

## Root Cause
Tempo was deployed **without the metrics generator component**, which is responsible for:
1. Generating span metrics from traces
2. Creating service graph metrics
3. Remote writing metrics to Prometheus/Mimir

## Solution

Update the Tempo Helm values in `/Users/jazziro/codesenju/repos/kubelab/addons/tempo.yaml` to enable metrics generator:

```yaml
metricsGenerator:
  enabled: true
  config:
    storage:
      remote_write:
        - url: http://mimir-nginx.grafana-system.svc.cluster.local/api/v1/push
          send_exemplars: true
    registry:
      external_labels:
        source: tempo
        cluster: kubelab
    processor:
      service_graphs:
        dimensions:
          - http.method
          - http.target
          - http.status_code
        histogram_buckets: [0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8]
        max_items: 10000
      span_metrics:
        dimensions:
          - http.method
          - http.target
          - http.status_code
        histogram_buckets: [0.002, 0.004, 0.008, 0.016, 0.032, 0.064, 0.128, 0.256, 0.512, 1.024, 2.048, 4.096, 8.192, 16.384]
```

## Implementation Steps

1. Update `addons/tempo.yaml` with metrics generator configuration
2. Apply the changes:
   ```bash
   cd /Users/jazziro/codesenju/repos/kubelab/ansible
   ansible-playbook ../addons/tempo.yaml --vault-pass-file=vault-pass.txt
   ```

3. Verify metrics generator pod is created:
   ```bash
   kubectl get pods -n grafana-system | grep metrics-generator
   ```

4. Wait 2-3 minutes for metrics to be generated and scraped

5. Verify metrics in Mimir:
   ```bash
   # Query Mimir for service graph metrics
   kubectl port-forward -n grafana-system svc/mimir-nginx 8080:80
   curl -s 'http://localhost:8080/prometheus/api/v1/query?query=traces_service_graph_request_total' | jq
   ```

6. Check service graph in Grafana Explore (Tempo datasource)

## Expected Metrics

Once configured, these metrics should appear in Mimir:
- `traces_service_graph_request_total` - Request count between services
- `traces_service_graph_request_failed_total` - Failed requests
- `traces_service_graph_request_server_seconds_bucket` - Server-side latency histogram
- `traces_service_graph_request_client_seconds_bucket` - Client-side latency histogram
- `traces_spanmetrics_calls_total` - Total span calls
- `traces_spanmetrics_duration_seconds_bucket` - Span duration histogram
- `traces_spanmetrics_duration_seconds_sum` - Sum of span durations
- `traces_spanmetrics_duration_seconds_count` - Count of spans

## Verification

After applying the fix:
1. Service graph should display in Tempo Explore view
2. Metrics should be queryable in Mimir
3. Dashboards using service graph data should populate

## References
- [Tempo Metrics Generator Documentation](https://grafana.com/docs/tempo/latest/metrics-generator/)
- [Tempo Service Graph](https://grafana.com/docs/tempo/latest/metrics-generator/service-graphs/)
- [Tempo Span Metrics](https://grafana.com/docs/tempo/latest/metrics-generator/span_metrics/)
