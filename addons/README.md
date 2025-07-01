# ArgoCD Applications

This directory contains ArgoCD application manifests for deploying applications to the Kubernetes cluster.

## Application Structure

Each YAML file defines an ArgoCD application that points to either:

1. A Helm chart with custom values
2. A Kustomize overlay with customizations
3. A combination of both using the ArgoCD multi-source feature

## Deployment Method

Applications can be deployed using Ansible:

```bash
ansible-playbook addons/<application>.yaml
```

Or applied directly with kubectl:

```bash
kubectl apply -f addons/<application>.yaml
```

## Available Applications

### Core Infrastructure

- `argocd.yaml` - ArgoCD deployment
- `cert-manager.yaml` - Certificate management
- `ingress-nginx.yaml` - NGINX ingress controller
- `metrics-server.yaml` - Kubernetes metrics server

### Monitoring & Observability

- `kube-prometheus-stack.yaml` - Prometheus, Alertmanager, and Grafana
- `headlamp.yaml` - Kubernetes web UI
- `goldilocks.yaml` - Resource recommendation tool

### Storage

- `minio.yaml` - MinIO S3-compatible object storage
- `cloudnative-postgresql.yaml` - PostgreSQL operator

### Development Tools

- `gitea.yaml` - Git server
- `gitea-database.yaml` - PostgreSQL database for Gitea
- `backstage.yaml` - Developer portal

### Media Applications

- `media-stack.yaml` - Media management applications

### Security & Authentication

- `vaultwarden.yaml` - Password manager
- `authentik.yaml` - Identity provider

### Networking

- `cloudflare-ddns.yaml` - Dynamic DNS updater
- `nginx-proxy-manager.yaml` - NGINX proxy manager

## Application Configuration

Most applications use external configuration from:

1. Helm values in the `/helm` directory
2. Kustomize overlays in the `/kustomize` directory

## Example Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: example-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/codesenju/kubelab.git
    path: kustomize/example-app/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: example-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Multi-Source Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: example-helm-app
  namespace: argocd
spec:
  project: default
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
  destination:
    server: https://kubernetes.default.svc
    namespace: example-helm-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```
