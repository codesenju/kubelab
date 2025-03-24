# kubelab
Kubernetes runnning on proxmomx

## Setup Infrastructure on Proxmox
```
tofu init
tofu plan -out=plan
tofu apply "plan"
```

## Setup K8s
```bash
ansible all -m ping
```
```bash
ansible-playbook -i inventory.ini nginx-lb.yaml
ansible-playbook -i inventory.ini kube-dependencies.yaml
ansible-playbook -i inventory.ini kube-cluster.yaml
```
## For Quick Setup
```
ansible-playbook -i inventory.ini main.yaml
```
### On master nodes(Optional)
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
# Bastion
ssh -i kubelab ubuntu@192.168.0.41 cat /home/ubuntu/.kube/config > ~/.kube/config

# Loadbalancer
```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

kubectl apply -f ext/metallb/metallb.yaml
```

# Cert-Manager
```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml
```
# CSI
ansible-playbook -i inventory.ini post.yaml

helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update
helm search repo democratic-csi/

helm upgrade \
--install \
--values freenas-iscsi.yaml \
--namespace democratic-csi \
zfs-iscsi democratic-csi/democratic-csi \
--create-namespace
# Argo-CD