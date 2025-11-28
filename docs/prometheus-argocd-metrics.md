# Scraping ArgoCD Metrics with Kube-Prometheus-Stack

This guide shows how to configure Prometheus to scrape ArgoCD metrics using ServiceMonitors, including common pitfalls and how to avoid them.

## Prerequisites

- ArgoCD installed via Helm
- Kube-Prometheus-Stack installed
- kubectl access to the cluster

## Common Mistakes to Avoid

⚠️ **CRITICAL MISTAKES** that will waste hours:

1. **Port Name Mismatch** - ArgoCD uses `http-metrics` as port name, NOT `metrics`
2. **Metrics Not Enabled** - ArgoCD doesn't expose metrics by default
3. **Wrong Label Selector** - ServiceMonitor must have `release: kube-prometheus-stack` label
4. **Creating Built-in ServiceMonitors** - Set `serviceMonitor.enabled: false` to avoid conflicts

## Step 1: Enable Metrics in ArgoCD (REQUIRED)

**Why this step:** ArgoCD doesn't expose metrics services by default. Without this, you'll have no endpoints to scrape.

Update your ArgoCD Helm values:

```yaml
controller:
  replicas: 1
  metrics:
    enabled: true              # ← MUST be true
    serviceMonitor:
      enabled: false            # ← MUST be false (we create custom ones)

server:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

repoServer:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

applicationSet:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
```

Apply the changes:
```bash
helm upgrade argocd argo/argo-cd -n argocd -f values.yaml
```

## Step 2: Verify Metrics Services Were Created

**Why this step:** Confirms Step 1 worked. If services don't exist, Prometheus has nothing to scrape.

```bash
kubectl get svc -n argocd | grep metrics
```

✅ **Expected output (4 services):**
```
argocd-application-controller-metrics      ClusterIP   10.x.x.x   <none>   8082/TCP
argocd-applicationset-controller-metrics   ClusterIP   10.x.x.x   <none>   8080/TCP
argocd-repo-server-metrics                 ClusterIP   10.x.x.x   <none>   8084/TCP
argocd-server-metrics                      ClusterIP   10.x.x.x   <none>   8083/TCP
```

❌ **If no services appear:** Metrics are not enabled. Go back to Step 1.

## Step 3: Check Service Port Names (CRITICAL)

**Why this step:** The port name MUST match what you put in ServiceMonitor. This is the #1 cause of "target not found" errors.

```bash
kubectl get svc -n argocd argocd-application-controller-metrics -o jsonpath='{.spec.ports[0].name}'
```

✅ **Expected output:** `http-metrics`

⚠️ **Common mistake:** Using `metrics` in ServiceMonitor when the actual port name is `http-metrics`

Check all services:
```bash
for svc in argocd-application-controller-metrics argocd-server-metrics argocd-repo-server-metrics argocd-applicationset-controller-metrics; do
  echo -n "$svc: "
  kubectl get svc -n argocd $svc -o jsonpath='{.spec.ports[0].name}'
  echo
done
```

All should return: `http-metrics`

## Step 4: Test Metrics Endpoints

**Why this step:** Verifies metrics are actually being exposed before configuring Prometheus.

```bash
kubectl run curl-test -n argocd --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -s http://argocd-application-controller-metrics:8082/metrics | head -20
```

✅ **Expected output:** Prometheus-format metrics
```
# HELP argocd_app_info Information about application.
# TYPE argocd_app_info gauge
argocd_app_info{...} 1
```

❌ **If connection refused:** Pods aren't ready or metrics not enabled
❌ **If 404:** Wrong port or path

## Step 5: Find Prometheus ServiceMonitor Selector

**Why this step:** Your ServiceMonitor MUST have this exact label or Prometheus will ignore it.

```bash
kubectl get prometheus -n kube-prometheus-stack kube-prometheus-stack-prometheus -o jsonpath='{.spec.serviceMonitorSelector}'
```

✅ **Expected output:**
```json
{"matchLabels":{"release":"kube-prometheus-stack"}}
```

📝 **Remember this label:** `release: kube-prometheus-stack`

## Step 6: Create ServiceMonitors with Correct Configuration

**Why this step:** Tells Prometheus where and how to scrape ArgoCD metrics.

⚠️ **CRITICAL:** Use `http-metrics` as port name (from Step 3), NOT `metrics`

Create file `argocd-servicemonitors.yaml`:

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: argocd
  labels:
    release: kube-prometheus-stack  # ← MUST match Step 5
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  endpoints:
    - port: http-metrics  # ← MUST be http-metrics, NOT metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-server-metrics
  namespace: argocd
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-server-metrics
  endpoints:
    - port: http-metrics  # ← MUST be http-metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-repo-server-metrics
  namespace: argocd
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-repo-server
  endpoints:
    - port: http-metrics  # ← MUST be http-metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-applicationset-controller-metrics
  namespace: argocd
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-applicationset-controller
  endpoints:
    - port: http-metrics  # ← MUST be http-metrics
```

Apply:
```bash
kubectl apply -f argocd-servicemonitors.yaml
```

## Step 7: Verify ServiceMonitors Were Created

```bash
kubectl get servicemonitor -n argocd
```

✅ **Expected output (4 ServiceMonitors):**
```
NAME                                       AGE
argocd-applicationset-controller-metrics   10s
argocd-metrics                             10s
argocd-repo-server-metrics                 10s
argocd-server-metrics                      10s
```

## Step 8: Verify Label Matching

**Why this step:** Catches configuration errors before waiting for Prometheus to reload.

Check ServiceMonitor has correct label:
```bash
kubectl get servicemonitor -n argocd argocd-metrics -o jsonpath='{.metadata.labels.release}'
```

✅ **Expected output:** `kube-prometheus-stack`

Check ServiceMonitor selector matches service:
```bash
# Get ServiceMonitor selector
kubectl get servicemonitor -n argocd argocd-metrics -o jsonpath='{.spec.selector.matchLabels}'

# Get Service labels
kubectl get svc -n argocd argocd-application-controller-metrics -o jsonpath='{.metadata.labels}'
```

The service MUST have `app.kubernetes.io/name: argocd-metrics` label.

## Step 9: Wait for Prometheus to Reload

**Why this step:** Prometheus reloads configuration every 30-60 seconds. Being impatient causes confusion.

```bash
echo "Waiting 90 seconds for Prometheus to reload..."
sleep 90
```

Optional - Force reload (not usually needed):
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload
```

## Step 10: Verify Prometheus Discovered Targets

**Why this step:** Confirms Prometheus found and is scraping ArgoCD.

```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.namespace=="argocd") | "\(.labels.job) - \(.health)"'
```

✅ **Expected output (all should be "up"):**
```
argocd-application-controller-metrics - up
argocd-applicationset-controller-metrics - up
argocd-repo-server-metrics - up
argocd-server-metrics - up
```

❌ **If empty:** ServiceMonitor labels don't match Prometheus selector (go back to Step 5-6)
❌ **If "down":** Metrics endpoint not accessible (go back to Step 4)

## Step 11: Query ArgoCD Metrics

**Why this step:** Final confirmation that metrics are being scraped and stored.

```bash
# Check how many applications are being monitored
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=argocd_app_info' 2>/dev/null | \
  jq -r '.data.result | length'
```

✅ **Expected output:** Number > 0 (number of ArgoCD applications)

List application names:
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=argocd_app_info' 2>/dev/null | \
  jq -r '.data.result[0:5][] | .metric.name'
```

Query sync status:
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=argocd_app_sync_total' 2>/dev/null | \
  jq '.data.result | length'
```

## Troubleshooting Decision Tree

### Problem: No targets appearing in Prometheus

**Step 1:** Check ServiceMonitor labels
```bash
kubectl get servicemonitor -n argocd argocd-metrics -o jsonpath='{.metadata.labels}'
```
- Missing `release: kube-prometheus-stack`? → Add it and reapply

**Step 2:** Check Prometheus selector
```bash
kubectl get prometheus -n kube-prometheus-stack kube-prometheus-stack-prometheus -o jsonpath='{.spec.serviceMonitorSelector}'
```
- Doesn't match ServiceMonitor labels? → Update ServiceMonitor labels

**Step 3:** Restart Prometheus Operator
```bash
kubectl delete pod -n kube-prometheus-stack -l app=kube-prometheus-stack-operator
sleep 60
```

### Problem: Targets showing as "down"

**Step 1:** Test endpoint directly
```bash
kubectl run curl-test -n argocd --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -v http://argocd-application-controller-metrics:8082/metrics
```
- Connection refused? → Metrics not enabled (go to Step 1)
- 404? → Wrong port or path

**Step 2:** Check pod logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Problem: Targets found but no metrics in queries

**Step 1:** Check scrape errors
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq '.data.activeTargets[] | select(.labels.namespace=="argocd") | {job: .labels.job, lastError: .lastError}'
```

**Step 2:** Verify scrape is happening
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq '.data.activeTargets[] | select(.labels.namespace=="argocd") | {job: .labels.job, lastScrape: .lastScrape}'
```

## Common Error Messages and Solutions

### "no endpoints available for service"
**Cause:** Service exists but no pods are backing it
**Solution:** Check if ArgoCD pods are running
```bash
kubectl get pods -n argocd
```

### "port not found"
**Cause:** Port name in ServiceMonitor doesn't match service port name
**Solution:** Use `http-metrics` not `metrics` (see Step 3)

### "no matching services"
**Cause:** ServiceMonitor selector doesn't match service labels
**Solution:** Check label matching (see Step 8)

### "ServiceMonitor not found by Prometheus"
**Cause:** Missing `release: kube-prometheus-stack` label
**Solution:** Add label to ServiceMonitor metadata (see Step 6)

## Available ArgoCD Metrics

### Application Controller (port 8082)
- `argocd_app_info` - Application status (sync_status, health_status)
- `argocd_app_sync_total` - Total sync operations
- `argocd_app_reconcile` - Reconciliation duration
- `argocd_cluster_connection_status` - Cluster connectivity

### API Server (port 8083)
- `argocd_redis_request_total` - Redis operations
- `grpc_server_handled_total` - gRPC requests

### Repo Server (port 8084)
- `argocd_git_request_total` - Git operations
- `argocd_git_request_duration_seconds` - Git latency

### ApplicationSet Controller (port 8080)
- `argocd_appset_info` - ApplicationSet status
- `argocd_appset_reconcile` - Reconciliation performance

## Grafana Dashboard

Import official ArgoCD dashboard:
1. Go to Grafana → Dashboards → Import
2. Enter dashboard ID: `14584`
3. Select Prometheus datasource
4. Click Import

Or download from: https://github.com/argoproj/argo-cd/blob/master/examples/dashboard.json

## Quick Reference Commands

```bash
# Check everything is configured
kubectl get svc,servicemonitor -n argocd | grep metrics

# Verify targets
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.namespace=="argocd") | "\(.labels.job) - \(.health)"'

# Query metrics
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=argocd_app_info' 2>/dev/null | jq .

# Force Prometheus reload
kubectl delete pod -n kube-prometheus-stack -l app=kube-prometheus-stack-operator
```

## Checklist

- [ ] Metrics enabled in ArgoCD Helm values
- [ ] 4 metrics services exist in argocd namespace
- [ ] Service port names are `http-metrics`
- [ ] Metrics endpoints return data (curl test)
- [ ] ServiceMonitors have `release: kube-prometheus-stack` label
- [ ] ServiceMonitors use `http-metrics` as port name
- [ ] Waited 90+ seconds after creating ServiceMonitors
- [ ] All 4 targets show as "up" in Prometheus
- [ ] Metrics queryable (argocd_app_info returns data)

## References

- [ArgoCD Metrics Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/metrics/)
- [Prometheus Operator ServiceMonitor](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.ServiceMonitor)
