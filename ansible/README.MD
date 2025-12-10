# Ansible Configuration for Kubernetes Deployment

This directory contains Ansible playbooks and configurations for deploying and managing the Kubernetes cluster.

## Directory Structure

- `inventory.ini` - Inventory file with host definitions
- `main.yaml` - Main playbook for cluster deployment
- `roles/` - Ansible roles for different components
- `templates/` - Jinja2 templates for configuration files

## Prerequisites

- Ansible 2.9 or higher
- SSH access to all nodes
- Python 3.x on all nodes

## Usage

### Verify Connectivity

Before running playbooks, verify that Ansible can connect to all nodes:

```bash
ansible all -m ping
```

### Deploy Kubernetes Cluster

```bash
ansible-playbook main.yaml --tags k8s
```

### Deploy Specific Components

```bash
ansible-playbook main.yaml --tags <tag>
```

Available tags:
- `k8s` - Deploy Kubernetes components
- `storage` - Configure storage
- `networking` - Configure networking
- `monitoring` - Deploy monitoring stack
- `adhoc` - Run adhoc tasks

### Ad-hoc Commands

Enable volume expansion for storage classes:

```bash
ansible-playbook main.yaml --tags adhoc,enable_volume_expansion
```

## Configuration

### Inventory

The inventory file (`inventory.ini`) defines the hosts and their roles:

```ini
[control_plane]
k8s-control-plane-1 ansible_host=192.168.0.41
k8s-control-plane-2 ansible_host=192.168.0.42

[workers]
k8s-worker-1 ansible_host=192.168.0.51
k8s-worker-2 ansible_host=192.168.0.52

[lb]
k8s-lb ansible_host=192.168.0.40
```

### Variables

Common variables are defined in `group_vars/all.yaml`. Host-specific variables can be defined in `host_vars/`.

## Playbooks

### main.yaml

The main playbook that orchestrates the deployment of the entire cluster.

### addons.yaml

Deploys additional components and applications to the cluster.

## Roles

- `common` - Common configuration for all nodes
- `kubernetes` - Kubernetes installation and configuration
- `storage` - Storage configuration
- `networking` - Networking configuration
- `monitoring` - Monitoring stack deployment

## Troubleshooting

If you encounter issues during deployment:

1. Check connectivity to all nodes
2. Verify that all prerequisites are met
3. Run the playbook with increased verbosity:

```bash
ansible-playbook main.yaml --tags k8s -vvv
```

### NFS Storage Permission Issues

When using TrueNAS NFS storage, applications may fail with permission errors. Common symptoms:
- PostgreSQL: "data directory has wrong ownership" or "Operation not permitted"
- Redis: "Can't open or create append-only dir: Permission denied"

**Solution**: Fix ownership on TrueNAS server:

```bash
# SSH to TrueNAS and fix permissions for specific applications
ssh -i ~/codesenju/kubelab.pem root@192.168.0.16

# For Authentik (PostgreSQL uses 1001:1001, Redis uses 1001:1001)
chown -R 1001:1001 /mnt/pool1/AppData/authentik/database
chown -R 1001:1001 /mnt/pool1/AppData/authentik/redis

# For other apps, check the securityContext.runAsUser in the pod spec
kubectl get pod <pod-name> -o yaml | grep -A5 securityContext
```

**Prevention**: Use initContainers in Helm values to automatically fix permissions:

```yaml
postgresql:
  primary:
    initContainers:
      - name: volume-permissions
        image: busybox:1.35
        command: ['sh', '-c', 'chown -R 1001:1001 /bitnami/postgresql && chmod -R 755 /bitnami/postgresql']
        volumeMounts:
          - name: data
            mountPath: /bitnami/postgresql
        securityContext:
          runAsUser: 0
```

**Note**: This setup uses UID/GID 1001:1001 for both PostgreSQL and Redis containers.
