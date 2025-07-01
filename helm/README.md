# Helm Values

This directory contains Helm values files for applications deployed in the Kubernetes cluster.

## Usage

These values files are referenced by ArgoCD applications using the multi-source feature:

```yaml
sources:
  - repoURL: https://charts.example.com
    chart: example-chart
    targetRevision: 1.0.0
    helm:
      valueFiles:
        - $values/helm/example_values.yaml
  - repoURL: https://github.com/codesenju/kubelab.git
    targetRevision: main
    ref: values
```

## Available Values Files

### Core Infrastructure

- `ingress_nginx_values.yaml` - NGINX Ingress Controller configuration
- `cert_manager_values.yaml` - Cert-Manager configuration

### Monitoring & Observability

- `kube_prometheus_stack_values.yaml` - Prometheus, Alertmanager, and Grafana configuration
- `headlamp_values.yaml` - Kubernetes web UI configuration

### Storage

- `minio_operator_values.yaml` - MinIO Operator configuration
- `minio_s3_tenant_values.yaml` - MinIO S3 tenant configuration

### Development Tools

- `gitea_values.yaml` - Gitea configuration

## Customization

### Updating Values

1. Modify the values file with your desired configuration
2. Commit and push the changes
3. ArgoCD will automatically detect the changes and update the application

### Adding New Values Files

1. Create a new values file for your application
2. Reference it in the corresponding ArgoCD application manifest
3. Deploy the application

## Best Practices

1. **Document Values**: Add comments to explain non-obvious settings
2. **Use Consistent Formatting**: Maintain consistent YAML formatting
3. **Version Control**: Track changes to values files in Git
4. **Minimize Customization**: Only override values that differ from defaults
5. **Test Changes**: Test values changes in a development environment first

## Example Values File

```yaml
# Example Helm values for nginx-ingress
controller:
  replicaCount: 2
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  service:
    type: LoadBalancer
    externalTrafficPolicy: Local
  metrics:
    enabled: true
  config:
    use-forwarded-headers: "true"
    proxy-buffer-size: "16k"
```
