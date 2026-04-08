# 🤖 Ansible Configuration for Kubernetes Deployment

<p align="center">
  <img src="https://img.shields.io/badge/Ansible-2.9+-red?style=flat&logo=ansible" alt="Ansible">
  <img src="https://img.shields.io/badge/Kubernetes-1.28+-blue?style=flat&logo=kubernetes" alt="Kubernetes">
</p>

This directory contains Ansible playbooks and configurations for deploying and managing the Kubernetes cluster.

---

## 📁 Directory Structure

| File/Directory  | Description                              |
| --------------- | ---------------------------------------- |
| `inventories/`  | Environment-specific inventories (`local`, `prod`) |
| `main.yaml`     | Main playbook for cluster deployment     |
| `roles/`        | Ansible roles for different components   |
| `templates/`    | Jinja2 templates for configuration files |

---

## ✅ Prerequisites

- [OpenTofu Infrastructure](../tofu/README.md) - Set up the infrastructure first
- Ansible 2.9 or higher
- SSH access to all nodes
- Python 3.x on all nodes

---

## 🚀 Usage

### Verify Connectivity

Before running playbooks, verify that Ansible can connect to all nodes:

```bash
export ANSIBLE_CONFIG=ansible.cfg
export INVENTORY=inventories/local/hosts.ini
```

```bash
ansible -i "$INVENTORY" all -m ping
```

### Deploy Kubernetes Cluster

```bash
ansible-playbook -i "$INVENTORY" main.yaml
```

### Deploy Specific Components

```bash
ansible-playbook -i "$INVENTORY" main.yaml --tags <tag>
```

#### Available Tags

| Tag          | Description                  |
| ------------ | ---------------------------- |
| `k8s`        | Deploy Kubernetes components |
| `storage`    | Configure storage            |
| `networking` | Configure networking         |
| `monitoring` | Deploy monitoring stack      |
| `adhoc`      | Run adhoc tasks              |

### Ad-hoc Commands

Enable volume expansion for storage classes:

```bash
ansible-playbook -i "$INVENTORY" main.yaml --tags adhoc,enable_volume_expansion
```

---

## ⚙️ Configuration

### Inventory

Inventories are separated by environment:

- `inventories/local/hosts.ini`
- `inventories/prod/hosts.ini`

Example:

```ini
[control-plane]
k8s-control-plane-1 ansible_host=192.168.0.41

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/codesenju/kubelab.pem
```

Use the environment you want at runtime:

```bash
ansible-playbook -i inventories/local/hosts.ini main.yaml
ansible-playbook -i inventories/prod/hosts.ini main.yaml
```

### Variables

Common variables are defined in `group_vars/all.yaml`. Host-specific variables can be defined in `host_vars/`.

---

## 📖 Playbooks

### main.yaml

The main playbook that orchestrates the deployment of the entire cluster.

### addons.yaml

Deploys additional components and applications to the cluster.

---

## 🛠️ Roles

| Role         | Description                               |
| ------------ | ----------------------------------------- |
| `common`     | Common configuration for all nodes        |
| `kubernetes` | Kubernetes installation and configuration |
| `storage`    | Storage configuration                     |
| `networking` | Networking configuration                  |
| `monitoring` | Monitoring stack deployment               |

---

<p align="center">
  <sub>Built with ❤️ for the Kubernetes community</sub>
</p>
