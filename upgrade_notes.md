```bash
export k8s_version=1.33

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo apt update
```

```bash
sudo apt-cache madison kubeadm
```
```bash
export k8s_ver=1.33.9-1.1
```
```bash
sudo apt-mark unhold kubeadm && \
sudo apt-get update && sudo apt-get install -y kubeadm=$k8s_ver && \
sudo apt-mark hold kubeadm
```

```bash
kubeadm version -o short
```

```bash
sudo kubeadm upgrade plan
```
```bash
sudo kubeadm upgrade node
```
## Upgrade kubelet & kubectl
```bash
sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet=$k8s_ver kubectl=$k8s_ver && \
sudo apt-mark hold kubelet kubectl
```
```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```
## Issues
##### Error
```bash
ubuntu@k8s-control-plane-1:~$ sudo kubeadm upgrade plan
[preflight] Running pre-flight checks.
[upgrade/config] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[upgrade/config] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.
[upgrade/init config] FATAL: failed to get node registration: node k8s-control-plane-1 doesn't have kubeadm.alpha.kubernetes.io/cri-socket annotation
To see the stack trace of this error execute with --v=5 or higher
```

##### Solution

```bash
kubectl annotate node k8s-control-plane-1 \
  kubeadm.alpha.kubernetes.io/cri-socket='unix:///run/containerd/containerd.sock' \
  --overwrite
```

```bash
# verify
kubectl get node k8s-control-plane-1 -o jsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/cri-socket}{"\n"}'
```

##### Error
```bash
ubuntu@k8s-control-plane-1:~$ sudo kubeadm upgrade plan
[preflight] Running pre-flight checks.
[upgrade/config] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[upgrade/config] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.
[upgrade/init config] FATAL: this version of kubeadm only supports deploying clusters with the control plane version >= 1.33.0. Current version: v1.30.12
To see the stack trace of this error execute with --v=5 or higher
```
##### Solution
```bash
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}'

kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > /tmp/ClusterConfiguration.yaml
sed -i 's/kubernetesVersion: v1.30.12/kubernetesVersion: v1.33.13/' /tmp/ClusterConfiguration.yaml
sudo kubeadm init phase upload-config kubeadm --config /tmp/ClusterConfiguration.yaml
```
# ETCD

sudo echo '192.168.0.16:/mnt/pool2/kubernetes /opt/kubernetes nfs rw,hard,intr,noatime,_netdev,vers=4.1 0 0' >> /etc/fstab
sudo mkdir -p /opt/kubernetes
sudo mount -a
df -h /opt/kubernetes
Stop all 3 Control Planes

sudo mkdir -p /etc/kubernetes/manifests-backup
sudo sh -c 'mv /etc/kubernetes/manifests/*.yaml /etc/kubernetes/manifests-backup/'

# Verify pods are stopped

sudo crictl ps | grep etcd

# Define your variables for clarity

export NODE_1_IP="192.168.0.41"
export NODE_2_IP="192.168.0.42"
export NODE_3_IP="192.168.0.43"

export SNAPSHOT_PATH="/opt/kubernetes/etcd-snapshot_2026-04-03_00h00.db"

sudo mv /var/lib/etcd/ /var/lib/etcd.bak
sudo mkdir -p /var/lib/etcd -p

sudo ETCDCTL_API=3 etcdutl snapshot restore $SNAPSHOT_PATH \
  --name k8s-control-plane-1 \
  --initial-cluster "k8s-control-plane-1=https://${NODE_1_IP}:2380,k8s-control-plane-2=https://${NODE_2_IP}:2380,k8s-control-plane-3=https://${NODE_3_IP}:2380" \
 --initial-cluster-token etcd-cluster-1 \
 --initial-advertise-peer-urls https://${NODE_1_IP}:2380 \
 --data-dir /var/lib/etcd

On CP-Node-2:
Run the same command as above, but change --name cp-node-2 and --initial-advertise-peer-urls https://${NODE_2_IP}:2380

sudo ETCDCTL_API=3 etcdutl snapshot restore $SNAPSHOT_PATH \
  --name k8s-control-plane-2 \
  --initial-cluster "k8s-control-plane-1=https://${NODE_1_IP}:2380,k8s-control-plane-2=https://${NODE_2_IP}:2380,k8s-control-plane-3=https://${NODE_3_IP}:2380" \
 --initial-cluster-token etcd-cluster-1 \
 --initial-advertise-peer-urls https://${NODE_2_IP}:2380 \
 --data-dir /var/lib/etcd

On CP-Node-3:
Run the same command as above, but change --name cp-node-3 and --initial-advertise-peer-urls https://${NODE_3_IP}:2380

sudo ETCDCTL_API=3 etcdutl snapshot restore $SNAPSHOT_PATH \
  --name k8s-control-plane-3 \
  --initial-cluster "k8s-control-plane-1=https://${NODE_1_IP}:2380,k8s-control-plane-2=https://${NODE_2_IP}:2380,k8s-control-plane-3=https://${NODE_3_IP}:2380" \
 --initial-cluster-token etcd-cluster-1 \
 --initial-advertise-peer-urls https://${NODE_3_IP}:2380 \
 --data-dir /var/lib/etcd

5. Update Manifests and Restart (All 3 Nodes)
r the etcd-data volume to /var/lib/etcd-from-backup.

    Move the files back:

sudo sh -c 'mv /etc/kubernetes/manifests-backup/*.yaml /etc/kubernetes/manifests/'

# Run this from any control plane node

sudo kubectl exec -n kube-system etcd-k8s-control-plane-1 -- etcdctl \
 --endpoints=https://127.0.0.1:2379 \
 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
 --cert=/etc/kubernetes/pki/etcd/server.crt \
 --key=/etc/kubernetes/pki/etcd/server.key \
 endpoint health -w table

sudo kubectl exec -n kube-system etcd-k8s-control-plane-1 -- etcdctl \
 --endpoints=https://127.0.0.1:2379 \
 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
 --cert=/etc/kubernetes/pki/etcd/server.crt \
 --key=/etc/kubernetes/pki/etcd/server.key \
 member list -w table

For a full cluster-wide check, run this from one control-plane node:

sudo kubectl exec -n kube-system etcd-k8s-control-plane-1 -- etcdctl \
  --endpoints=https://192.168.0.41:2379,https://192.168.0.42:2379,https://192.168.0.43:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status -w table

Use this to label the three control-plane nodes so ROLES shows control-plane:
kubectl label node k8s-control-plane-1 node-role.kubernetes.io/control-plane=""
kubectl label node k8s-control-plane-2 node-role.kubernetes.io/control-plane=""
kubectl label node k8s-control-plane-3 node-role.kubernetes.io/control-plane=""

For workers, use:
kubectl label node k8s-worker-1 node-role.kubernetes.io/worker=""
kubectl label node k8s-worker-2 node-role.kubernetes.io/worker=""
kubectl label node k8s-worker-3 node-role.kubernetes.io/worker=""

## Rsync
```bash
nohup rsync -ahvP --numeric-ids /mnt/pool1/AppData/rustfs /mnt/pool2/AppData/ > rsync.log 2>&1 &
```