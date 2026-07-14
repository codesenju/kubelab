# Inventory Environments

- `oci/hosts.ini`: OCI VM inventory
- `prod/hosts.ini`: homelab (Proxmox) inventory

Use with playbooks:

```bash
ansible-playbook -i ansible/inventories/oci/hosts.ini addons/argocd.yaml --vault-password-file ~/vault-password.txt
ansible-playbook -i ansible/inventories/prod/hosts.ini addons/argocd.yaml --vault-password-file ~/vault-password.txt
```
