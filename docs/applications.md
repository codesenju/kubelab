# Applications Overview

This document provides an overview of the applications deployed in the Kubelab Kubernetes cluster.

## Core Infrastructure

### ArgoCD

[ArgoCD](https://argoproj.github.io/cd/) is the GitOps continuous delivery tool used to manage application deployments.

- **Namespace**: `argocd`
- **Access**: https://argocd.local.jazziro.com
- **Authentication**: Integrated with Authentik

### Ingress NGINX

[NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/) manages external access to services.

- **Namespace**: `ingress-nginx`
- **Configuration**: [ingress_nginx_values.yaml](../helm/ingress_nginx_values.yaml)

### Cert-Manager

[Cert-Manager](https://cert-manager.io/) automates certificate management.

- **Namespace**: `cert-manager`

## Monitoring & Observability

### Kube-Prometheus-Stack

[Prometheus Operator](https://github.com/prometheus-operator/kube-prometheus) provides monitoring and alerting.

- **Namespace**: `kube-prometheus-stack`
- **Components**: Prometheus, Alertmanager, Grafana
- **Configuration**: [kube_prometheus_stack_values.yaml](../helm/kube_prometheus_stack_values.yaml)

### Headlamp

[Headlamp](https://headlamp.dev/) is a web UI for Kubernetes.

- **Namespace**: `headlamp`
- **Configuration**: [headlamp_values.yaml](../helm/headlamp_values.yaml)

## Storage

### MinIO S3

[MinIO](https://min.io/) provides S3-compatible object storage.

- **Namespace**: `minio-s3`
- **Configuration**: [minio_s3_tenant_values.yaml](../helm/minio_s3_tenant_values.yaml)

## Development Tools

### Gitea

[Gitea](https://gitea.io/) is a self-hosted Git service.

- **Namespace**: `gitea`
- **Database**: PostgreSQL (deployed separately)

### Backstage

[Backstage](https://backstage.io/) is a developer portal platform.

- **Namespace**: `backstage`
- **Configuration**: [kustomize/backstage](../kustomize/backstage/)

## Media Applications

### Media Stack

A collection of media management applications.

- **Namespace**: `media-stack`
- **Components**: Jellyfin, Sonarr, Radarr, etc.
- **Configuration**: [kustomize/media-stack](../kustomize/media-stack/)

## Security & Authentication

### Vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) is a Bitwarden-compatible password manager.

- **Namespace**: `vaultwarden`
- **Configuration**: [kustomize/vaultwarden](../kustomize/vaultwarden/)

### Authentik

[Authentik](https://goauthentik.io/) provides identity management and SSO.

- **Namespace**: `authentik`

## Networking

### Cloudflare DDNS

Updates Cloudflare DNS records with the current public IP.

- **Namespace**: `cloudflare-ddns`
- **Configuration**: [kustomize/ddns](../kustomize/ddns/)

### NGINX Proxy Manager

[NGINX Proxy Manager](https://nginxproxymanager.com/) provides a web UI for NGINX proxy configuration.

- **Namespace**: `nginx-proxy-manager`
- **Configuration**: [kustomize/nginx-proxy-manager](../kustomize/nginx-proxy-manager/)

## Deploying Applications

Applications are deployed using ArgoCD and defined in the `/addons` directory. To deploy an application:

```bash
ansible-playbook ../addons/<application>.yaml
```

## Adding New Applications

1. Create a Helm values file or Kustomize overlay
2. Create an ArgoCD application manifest in the `/addons` directory
3. Deploy using Ansible or apply directly with `kubectl`
