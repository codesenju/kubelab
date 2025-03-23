# kubelab
Kubernetes runnning on proxmomx

Setup Infrastructure on Proxmox
```
tofu init
tofu plan
tofu apply --auto-approve
```
Setup K8s
```bash
ansible-playbook -i inventory.ini k8s-setup.yaml
```