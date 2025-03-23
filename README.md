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

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```