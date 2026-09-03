# Kubernetes Upgrade Notes

This runbook upgrades a kubeadm cluster one minor version at a time. The etcd
restore procedure is a separate disaster-recovery procedure and is not part of
a normal Kubernetes upgrade.

## Kubernetes Upgrade

Upgrade only one node at a time and verify cluster health before continuing.

### 1. Configure the Package Repository

Run on each node that will be upgraded:

```bash
export k8s_version=1.35

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo apt update
sudo apt-cache madison kubeadm
```

Set the exact package version selected from `apt-cache madison`:

```bash
export k8s_ver=1.35.8-1.1
```

### 2. Upgrade the First Control Plane

Run `upgrade plan` and `upgrade apply` on one control-plane node only,
normally `k8s-control-plane-1`:

```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$k8s_ver
sudo apt-mark hold kubeadm

kubeadm version -o short
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.35.8
```

Upgrade and restart kubelet and kubectl on the same node:

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$k8s_ver kubectl=$k8s_ver
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 3. Upgrade the Remaining Control Planes

Upgrade `k8s-control-plane-2` and `k8s-control-plane-3` separately. Wait for
each node to return to `Ready` before moving to the next node.

```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$k8s_ver
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node
```

Then upgrade and restart kubelet and kubectl using the commands in step 2.

### 4. Upgrade the Workers

Drain and upgrade one worker at a time:

```bash
kubectl drain k8s-worker-1 \
  --ignore-daemonsets \
  --delete-emptydir-data

sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$k8s_ver
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node
```

Upgrade and restart kubelet and kubectl, then make the worker schedulable:

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$k8s_ver kubectl=$k8s_ver
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon k8s-worker-1
```

Repeat for `k8s-worker-2` and `k8s-worker-3`.

### 5. Verify the Upgrade

```bash
kubectl get nodes
kubectl get pods -A
```

## Upgrade Troubleshooting

### Missing CRI Socket Annotation

If `kubeadm upgrade plan` reports that a node has no CRI socket annotation:

```bash
kubectl annotate node k8s-control-plane-1 \
  kubeadm.alpha.kubernetes.io/cri-socket='unix:///run/containerd/containerd.sock' \
  --overwrite

kubectl get node k8s-control-plane-1 \
  -o jsonpath='{.metadata.annotations.kubeadm\\.alpha\\.kubernetes\\.io/cri-socket}{"\\n"}'
```

Use the affected node name and the correct CRI socket for that node.

### Stale Cluster Configuration Version

Example error:

```text
error: [upgrade/init config] FATAL: this version of kubeadm only supports
deploying clusters with the control plane version >= 1.34.0. Current version:
v1.30.12
```

This means the `kubeadm-config` ConfigMap is stale. It does not necessarily
mean that the running control-plane nodes are still on that version. First
compare the live node versions with the stored configuration:

```bash
kubectl get nodes

kubectl -n kube-system get cm kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}'

kubectl -n kube-system get cm kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}' > /tmp/ClusterConfiguration.yaml
```

Back up the ConfigMap before editing the temporary file:

```bash
kubectl -n kube-system get cm kubeadm-config -o yaml \
  > /root/kubeadm-config-backup.yaml
```

Edit `kubernetesVersion` in `/tmp/ClusterConfiguration.yaml` to the actual
current control-plane version shown by `kubectl get nodes` (for example,
`v1.34.6`), not the version you are upgrading to. Then upload the corrected
configuration:

```bash
sudo kubeadm init phase upload-config kubeadm \
  --config /tmp/ClusterConfiguration.yaml

sudo kubeadm upgrade plan
```

### clusterCIDR Recommendation Warning

You may also see a warning such as:

```text
The recommended value for "clusterCIDR" in "KubeProxyConfiguration" is:
10.244.0.0/16; the provided value is: 10.0.0.0/16
```

This is a warning, not the cause of the failed upgrade. Keep the existing
value unless it is inconsistent with the CNI configuration used by the
cluster. Change it only as a deliberate networking change.

# etcd Snapshot Restore

This procedure is for restoring an etcd snapshot after data loss or corruption.
It is not required for a normal Kubernetes version upgrade. Take a current
backup and verify the snapshot path before proceeding. These commands stop the
control plane and replace its etcd data.

## 1. Prepare Restore Storage

```bash
echo '192.168.0.16:/mnt/pool2/kubernetes /opt/kubernetes nfs rw,hard,intr,noatime,_netdev,vers=4.1 0 0' \
  | sudo tee -a /etc/fstab

sudo mkdir -p /opt/kubernetes
sudo mount -a
df -h /opt/kubernetes
```

## 2. Stop the Static Pods

Perform this on each control-plane node. Do not continue until the etcd static
pod has stopped on that node.

```bash
sudo mkdir -p /etc/kubernetes/manifests-backup
sudo sh -c 'mv /etc/kubernetes/manifests/*.yaml /etc/kubernetes/manifests-backup/'
sudo crictl ps | grep etcd
```

## 3. Define Restore Variables

Use the actual node IPs and a verified snapshot path:

```bash
export NODE_1_IP="192.168.0.41"
export NODE_2_IP="192.168.0.42"
export NODE_3_IP="192.168.0.43"
export SNAPSHOT_PATH="/opt/kubernetes/etcd-snapshot_2026-04-03_00h00.db"
```

## 4. Back Up Existing etcd Data

Run on each control-plane node before restoring:

```bash
sudo mv /var/lib/etcd /var/lib/etcd.bak
sudo mkdir -p /var/lib/etcd
```

## 5. Restore the Snapshot

Run the matching command on each control-plane node. The member name and
advertise URL must match the node.

### Control Plane 1

```bash
sudo ETCDCTL_API=3 etcdutl snapshot restore "$SNAPSHOT_PATH" \
  --name k8s-control-plane-1 \
  --initial-cluster "k8s-control-plane-1=https://${NODE_1_IP}:2380,k8s-control-plane-2=https://${NODE_2_IP}:2380,k8s-control-plane-3=https://${NODE_3_IP}:2380" \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls "https://${NODE_1_IP}:2380" \
  --data-dir /var/lib/etcd
```

### Control Plane 2

```bash
sudo ETCDCTL_API=3 etcdutl snapshot restore "$SNAPSHOT_PATH" \
  --name k8s-control-plane-2 \
  --initial-cluster "k8s-control-plane-1=https://${NODE_1_IP}:2380,k8s-control-plane-2=https://${NODE_2_IP}:2380,k8s-control-plane-3=https://${NODE_3_IP}:2380" \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls "https://${NODE_2_IP}:2380" \
  --data-dir /var/lib/etcd
```

### Control Plane 3

```bash
sudo ETCDCTL_API=3 etcdutl snapshot restore "$SNAPSHOT_PATH" \
  --name k8s-control-plane-3 \
  --initial-cluster "k8s-control-plane-1=https://${NODE_1_IP}:2380,k8s-control-plane-2=https://${NODE_2_IP}:2380,k8s-control-plane-3=https://${NODE_3_IP}:2380" \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls "https://${NODE_3_IP}:2380" \
  --data-dir /var/lib/etcd
```

## 6. Restore the Manifests

Before restoring the manifests, confirm that the etcd manifest points to the
restored data directory. Then run this on each control-plane node:

```bash
sudo sh -c 'mv /etc/kubernetes/manifests-backup/*.yaml /etc/kubernetes/manifests/'
```

## 7. Verify etcd

Run from a control-plane node after all etcd members have started:

```bash
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

sudo kubectl exec -n kube-system etcd-k8s-control-plane-1 -- etcdctl \
  --endpoints=https://192.168.0.41:2379,https://192.168.0.42:2379,https://192.168.0.43:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status -w table
```

## 8. Verify Kubernetes

```bash
kubectl get nodes
kubectl get pods -A
```

# Other Notes

## Node Role Labels

```bash
kubectl label node k8s-control-plane-1 node-role.kubernetes.io/control-plane=""
kubectl label node k8s-control-plane-2 node-role.kubernetes.io/control-plane=""
kubectl label node k8s-control-plane-3 node-role.kubernetes.io/control-plane=""

kubectl label node k8s-worker-1 node-role.kubernetes.io/worker=""
kubectl label node k8s-worker-2 node-role.kubernetes.io/worker=""
kubectl label node k8s-worker-3 node-role.kubernetes.io/worker=""
```

## Rsync

```bash
nohup rsync -ahvP --numeric-ids \
  /mnt/pool1/AppData/rustfs /mnt/pool2/AppData/ > rsync.log 2>&1 &
```
