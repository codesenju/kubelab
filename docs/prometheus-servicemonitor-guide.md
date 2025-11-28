# Complete Guide: Scraping Metrics with Kube-Prometheus-Stack

This guide explains how to configure Prometheus to scrape metrics from any application using ServiceMonitors.

## Understanding the Components

### ServiceMonitor
A Kubernetes Custom Resource that tells Prometheus which services to scrape and how.

### Key Concepts
1. **Prometheus Operator** - Watches for ServiceMonitor resources
2. **Service** - Must have a metrics port exposed
3. **ServiceMonitor** - Defines scraping configuration
4. **Label Matching** - ServiceMonitor must match both Prometheus selector and Service labels

## Prerequisites

- Kube-Prometheus-Stack installed
- Application exposing metrics endpoint
- kubectl access to the cluster

## Step-by-Step Guide

### Step 1: Identify Prometheus ServiceMonitor Selector

Find what label Prometheus is looking for:

```bash
kubectl get prometheus -n kube-prometheus-stack kube-prometheus-stack-prometheus -o jsonpath='{.spec.serviceMonitorSelector}'
```

Example output:
```json
{"matchLabels":{"release":"kube-prometheus-stack"}}
```

**Important:** Your ServiceMonitor MUST have this label.

### Step 2: Check Namespace Selector

Verify if Prometheus watches all namespaces or specific ones:

```bash
kubectl get prometheus -n kube-prometheus-stack kube-prometheus-stack-prometheus -o jsonpath='{.spec.serviceMonitorNamespaceSelector}'
```

- Empty `{}` = watches all namespaces ✅
- Specific labels = only watches matching namespaces

### Step 3: Verify Your Application Service

Check if your application has a metrics service:

```bash
kubectl get svc -n <namespace> <service-name>
```

Example:
```bash
kubectl get svc -n myapp myapp-metrics
```

Check the service details:
```bash
kubectl get svc -n myapp myapp-metrics -o yaml
```

Key things to verify:
1. **Port name** - Note the port name (e.g., `metrics`, `http-metrics`)
2. **Labels** - Note the service labels
3. **Port number** - Confirm metrics port

Example service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-metrics
  namespace: myapp
  labels:
    app: myapp
    component: metrics
spec:
  ports:
  - name: http-metrics  # ← Note this name
    port: 8080
    targetPort: 8080
  selector:
    app: myapp
```

### Step 4: Test Metrics Endpoint

Verify the metrics endpoint is accessible:

```bash
kubectl run curl-test -n <namespace> --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -s http://<service-name>:<port>/metrics | head -20
```

Example:
```bash
kubectl run curl-test -n myapp --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -s http://myapp-metrics:8080/metrics | head -20
```

Expected output should show Prometheus-format metrics:
```
# HELP myapp_requests_total Total requests
# TYPE myapp_requests_total counter
myapp_requests_total 1234
```

### Step 5: Create ServiceMonitor

Create a ServiceMonitor that matches your service:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-metrics
  namespace: myapp  # Same namespace as your service
  labels:
    release: kube-prometheus-stack  # ← MUST match Prometheus selector from Step 1
spec:
  selector:
    matchLabels:
      app: myapp  # ← MUST match your service labels
      component: metrics
  endpoints:
    - port: http-metrics  # ← MUST match service port name from Step 3
      interval: 30s  # Optional: scrape interval
      path: /metrics  # Optional: defaults to /metrics
```

Apply the ServiceMonitor:
```bash
kubectl apply -f servicemonitor.yaml
```

### Step 6: Verify ServiceMonitor Creation

Check the ServiceMonitor was created:

```bash
kubectl get servicemonitor -n <namespace>
```

View details:
```bash
kubectl describe servicemonitor -n <namespace> <servicemonitor-name>
```

### Step 7: Wait for Prometheus to Reload

Prometheus reloads configuration every 30-60 seconds. Wait 1-2 minutes.

To force reload (optional):
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload
```

### Step 8: Verify Prometheus Configuration

Check if Prometheus added the scrape config:

```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/config 2>/dev/null | \
  jq -r '.data.yaml' | grep -A10 "myapp"
```

### Step 9: Check Prometheus Targets

Verify Prometheus discovered your service:

```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.namespace=="<namespace>") | "\(.labels.job) - \(.health) - \(.lastError // "OK")"'
```

Example:
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.namespace=="myapp") | "\(.labels.job) - \(.health) - \(.lastError // "OK")"'
```

Expected output:
```
myapp-metrics - up - OK
```

### Step 10: Query Your Metrics

Test querying your metrics:

```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=<metric_name>' 2>/dev/null | jq .
```

Example:
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=myapp_requests_total' 2>/dev/null | jq .
```

## Common Issues and Solutions

### Issue 1: Target Not Appearing

**Check 1:** ServiceMonitor labels match Prometheus selector
```bash
# Get Prometheus selector
kubectl get prometheus -n kube-prometheus-stack kube-prometheus-stack-prometheus -o jsonpath='{.spec.serviceMonitorSelector}'

# Get ServiceMonitor labels
kubectl get servicemonitor -n <namespace> <name> -o jsonpath='{.metadata.labels}'
```

**Solution:** Add the required label to ServiceMonitor:
```yaml
metadata:
  labels:
    release: kube-prometheus-stack  # ← Add this
```

---

**Check 2:** ServiceMonitor selector matches Service labels
```bash
# Get ServiceMonitor selector
kubectl get servicemonitor -n <namespace> <name> -o jsonpath='{.spec.selector}'

# Get Service labels
kubectl get svc -n <namespace> <service-name> -o jsonpath='{.metadata.labels}'
```

**Solution:** Update ServiceMonitor selector to match service labels.

---

**Check 3:** Port name matches
```bash
# Get ServiceMonitor port
kubectl get servicemonitor -n <namespace> <name> -o jsonpath='{.spec.endpoints[0].port}'

# Get Service port name
kubectl get svc -n <namespace> <service-name> -o jsonpath='{.spec.ports[0].name}'
```

**Solution:** Update ServiceMonitor to use correct port name.

### Issue 2: Target Shows as "Down"

**Check endpoint accessibility:**
```bash
kubectl run curl-test -n <namespace> --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -v http://<service-name>:<port>/metrics
```

**Check pod logs:**
```bash
kubectl logs -n <namespace> <pod-name>
```

### Issue 3: Metrics Not Showing in Prometheus

**Verify scrape is happening:**
```bash
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq '.data.activeTargets[] | select(.labels.job=="<job-name>") | {health: .health, lastScrape: .lastScrape, lastError: .lastError}'
```

**Check for scrape errors:**
```bash
kubectl logs -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus | grep -i error
```

## Advanced Configuration

### Custom Scrape Interval

```yaml
spec:
  endpoints:
    - port: http-metrics
      interval: 15s  # Scrape every 15 seconds
```

### Custom Metrics Path

```yaml
spec:
  endpoints:
    - port: http-metrics
      path: /custom/metrics  # Default is /metrics
```

### TLS Configuration

```yaml
spec:
  endpoints:
    - port: https-metrics
      scheme: https
      tlsConfig:
        insecureSkipVerify: true
```

### Basic Auth

```yaml
spec:
  endpoints:
    - port: http-metrics
      basicAuth:
        username:
          name: metrics-secret
          key: username
        password:
          name: metrics-secret
          key: password
```

### Relabeling

```yaml
spec:
  endpoints:
    - port: http-metrics
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod
```

## Complete Example

Here's a complete working example:

```yaml
---
# Application Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        ports:
        - name: http
          containerPort: 8080
        - name: metrics
          containerPort: 9090

---
# Metrics Service
apiVersion: v1
kind: Service
metadata:
  name: myapp-metrics
  namespace: myapp
  labels:
    app: myapp
spec:
  ports:
  - name: http-metrics
    port: 9090
    targetPort: 9090
  selector:
    app: myapp

---
# ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-metrics
  namespace: myapp
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: http-metrics
      interval: 30s
```

## Verification Checklist

- [ ] Application exposes metrics endpoint
- [ ] Service exists with correct port name
- [ ] ServiceMonitor created with correct labels
- [ ] ServiceMonitor selector matches service labels
- [ ] ServiceMonitor port matches service port name
- [ ] Prometheus selector matches ServiceMonitor labels
- [ ] Target appears in Prometheus UI (Status → Targets)
- [ ] Target status is "UP"
- [ ] Metrics queryable in Prometheus

## Quick Debug Commands

```bash
# 1. Check all components
kubectl get svc,servicemonitor -n <namespace>

# 2. Verify Prometheus discovered target
kubectl exec -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.namespace=="<namespace>")'

# 3. Test metrics endpoint
kubectl run curl-test -n <namespace> --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -s http://<service>:<port>/metrics

# 4. Check Prometheus logs
kubectl logs -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0 -c prometheus --tail=50

# 5. Restart Prometheus Operator (force reload)
kubectl delete pod -n kube-prometheus-stack -l app=kube-prometheus-stack-operator
```

## References

- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [ServiceMonitor API Reference](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#servicemonitor)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
