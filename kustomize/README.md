# Kustomize Configurations

This directory contains Kustomize configurations for applications deployed in the Kubernetes cluster.

## Directory Structure

Each application follows a standard structure:

```
application-name/
├── base/             # Base configuration
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── kustomization.yaml
└── overlays/         # Environment-specific overlays
    ├── prod/         # Production environment
    │   ├── kustomization.yaml
    │   └── patch.yaml
    └── dev/          # Development environment
        ├── kustomization.yaml
        └── patch.yaml
```

## Usage

Applications are deployed through ArgoCD, which references these Kustomize configurations.

For manual testing, you can apply a Kustomize overlay directly:

```bash
kubectl apply -k kustomize/application-name/overlays/prod
```

## Available Applications

### Media Stack

The media stack includes applications for media management:

- Jellyfin - Media server
- Sonarr - TV show management
- Radarr - Movie management
- Readarr - Book management
- Prowlarr - Indexer management
- Flaresolverr - Cloudflare bypass

### Beszel Agent

AI agent for Kubernetes management.

### Cloudflare DDNS

Updates Cloudflare DNS records with the current public IP.

### NGINX Proxy Manager

Web UI for NGINX proxy configuration.

### Vaultwarden

Bitwarden-compatible password manager.

## Customization

### Adding a New Application

1. Create a base directory with common resources
2. Create overlay directories for different environments
3. Define a kustomization.yaml file in each directory

Example base kustomization.yaml:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
- configmap.yaml
```

Example overlay kustomization.yaml:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
patchesStrategicMerge:
- patch.yaml
namespace: my-application
```

### Common Customizations

- **Image Updates**: Update container images in overlays
- **Resource Limits**: Adjust CPU and memory limits
- **Configuration**: Override ConfigMap values
- **Replicas**: Change the number of replicas

## Best Practices

1. Keep base configurations generic
2. Use overlays for environment-specific settings
3. Use strategic merge patches for small changes
4. Use JSON patches for more complex transformations
5. Maintain consistent structure across applications
