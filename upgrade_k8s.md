# 1.20.x to 1.30.x
## Update the repos
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" |   sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt-get update
apt-get install -y kubeadm=1.30.12-1.1  --allow-change-held-packages
shutdown -r now

## Upgrading control-plane nodes
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
### On the first control plane
sudo kubeadm upgrade apply 1.30.12-1.1
### The rest of the control planes
kubeadm upgrade node

### Upgrade kubelet
kubectl drain <node-to-drain> --ignore-daemonsets

apt list -a kubelet
apt list -a kubectl

sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet='1.30.12-1.1' kubectl='1.30.12-1.1' && \
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

kubectl uncordon <node-to-uncordon>


## Upgrading worker nodes
sudo apt-mark unhold kubeadm && \
sudo apt-get update && sudo apt-get install -y kubeadm='1.30.12-1.1' && \
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node

kubectl drain <node-to-drain> --ignore-daemonsets --delete-emptydir-data

sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet='1.30.12-1.1' kubectl='1.30.12-1.1' && \
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

kubectl uncordon <node-to-uncordon>