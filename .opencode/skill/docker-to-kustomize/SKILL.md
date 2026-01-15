# Docker to Kustomize Converter

Transforms Docker commands or Docker Compose files into Kubernetes Kustomize manifests and ArgoCD Application Ansible playbooks.

## When to use

- When migrating from Docker containers to Kubernetes
- When creating new ArgoCD Applications for existing Docker services
- When standardizing container deployments across the cluster

## Prerequisites

- Docker command with `--name`, `-p` (ports), `-v` (volumes), and image reference
- Or Docker Compose file with services, ports, volumes, and image configuration

## Input format

### Docker run command example
```bash
docker run -d \
  --name rustfs \
  -p 9000:9000 \
  -p 9001:9001 \
  -v /data:/data \
  rustfs/rustfs:latest
```

### Docker Compose example
```yaml
services:
  rustfs:
    image: rustfs/rustfs:latest
    container_name: rustfs
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - /data:/data
    restart: unless-stopped
```

## Transformation process

### 1. Parse input

Extract from Docker command:
- **Image**: `rustfs/rustfs:latest` (last argument)
- **Name**: `--name rustfs` (container name for deployment name)
- **Ports**: `-p 9000:9000 -p 9001:9001` (host:container mapping)
- **Volumes**: `-v /data:/data` (host:container path mapping)

Extract from Docker Compose:
- **Image**: `image:` field from service
- **Name**: `container_name:` or derive from service name
- **Ports**: `ports:` array (format: "host:container")
- **Volumes**: `volumes:` array (format: "host:container:options")

### 2. Create Kustomize base

Create directory structure:
```
kustomize/<app-name>/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── pvc.yaml
└── overlays/
    └── prod/
        └── kustomization.yaml
```

### 3. Generate deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app-name>
  labels:
    app: <app-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <app-name>
  template:
    metadata:
      labels:
        app: <app-name>
    spec:
      containers:
        - name: <app-name>
          image: IMAGE_PLACEHOLDER
          ports:
            - containerPort: <container-port-1>
              name: http-<app-name>-1
            - containerPort: <container-port-2>
              name: http-<app-name>-2
          # Add more ports if needed
          volumeMounts:
            - name: <app-name>-data
              mountPath: <container-volume-path>
      volumes:
        - name: <app-name>-data
          persistentVolumeClaim:
            claimName: <app-name>-data
```

### 4. Generate service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <app-name>
spec:
  selector:
    app: <app-name>
  ports:
    - protocol: TCP
      port: <host-port-1>
      targetPort: <container-port-1>
      name: http-<app-name>-1
    - protocol: TCP
      port: <host-port-2>
      targetPort: <container-port-2>
      name: http-<app-name>-2
  type: ClusterIP
```

### 5. Generate pvc.yaml

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app-name>-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### 6. Generate base kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
- pvc.yaml
```

### 7. Generate overlay kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: <app-name>

images:
- name: IMAGE_PLACEHOLDER
  newName: <image-name>
  newTag: <image-tag>

resources:
- ../../base
```

### 8. Generate ArgoCD Application Ansible playbook

Create `addons/<app-name>.yaml` with:

```yaml
- hosts: k8s-control-plane-1
  gather_facts: no
  become: no
  vars:
    namespace: <app-name>
  tasks:

    - name: Deploy <app-name> ArgoCD Application
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: <app-name>
            namespace: argocd
            finalizers:
              - resources-finalizer.argocd.argoproj.io
          spec:
            project: default
            source:
              repoURL: https://github.com/codesenju/kubelab.git
              path: kustomize/<app-name>/overlays/prod
              targetRevision: main
              kustomize:
                commonAnnotations:
                  argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
                labels:
                  app.kubernetes.io/instance: <app-name>-prod
            destination:
              server: https://kubernetes.default.svc
              namespace: '{{ namespace }}'
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
              syncOptions:
                - CreateNamespace=true
                - ServerSideApply=true
                - RespectIgnoreDifferences=true
      tags: <app-name>
```

## Output

The skill will create:
1. Kustomize base directory with deployment, service, PVC, and kustomization files
2. Kustomize overlay directory with production kustomization
3. Ansible playbook in `addons/<app-name>.yaml`

## Usage example

**Input:**
```bash
docker run -d \
  --name rustfs \
  -p 9000:9000 \
  -p 9001:9001 \
  -v /data:/data \
  rustfs/rustfs:latest
```

**Generated files:**
- `kustomize/rustfs/base/kustomization.yaml`
- `kustomize/rustfs/base/deployment.yaml`
- `kustomize/rustfs/base/service.yaml`
- `kustomize/rustfs/base/pvc.yaml`
- `kustomize/rustfs/overlays/prod/kustomization.yaml`
- `addons/rustfs.yaml`

## Notes

- Default replica count is 1 (adjust based on requirements)
- Default storage request is 1Gi (adjust based on requirements)
- Service type defaults to ClusterIP
- PVC access mode defaults to ReadWriteOnce
- All resources use consistent naming: `<app-name>` for deployment/service, `<app-name>-data` for PVC
- Image placeholder pattern: `IMAGE_PLACEHOLDER` replaced in overlay with actual image reference
