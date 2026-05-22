
## x86_64
brew install lima-additional-guestagents

## A multi-node cluster can be created by starting multiple instances of this template
## connected via the `lima:user-v2` network.
#
```bash
limactl start control-plane.yaml --name cp1
limactl start worker1.yaml --name worker-1
limactl start worker2.yaml --name worker-2
```
```bash
limactl shell cp1 sudo kubeadm token create --print-join-command

# or

eval $(limactl shell cp1 sudo kubeadm token create --print-join-command | \
sed -E 's/.*join ([^:]+):([0-9]+) --token ([^ ]+) --discovery-token-ca-cert-hash ([^ ]+)/HOST=\1 PORT=\2 TOKEN=\3 HASH=\4/')
```

```bash
limactl shell 
```

## 

```bash
sudo cp -a /etc/kubernetes/pki /etc/kubernetes/pki.bak.$(date +%F-%H%M%S)

cat >/tmp/kubeadm-clusterconfig.yaml <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: kubernetes
kubernetesVersion: v1.33.10
controlPlaneEndpoint: 192.168.104.4:6443
certificatesDir: /etc/kubernetes/pki
imageRepository: registry.k8s.io
networking:
  dnsDomain: cluster.local
  podSubnet: 10.200.0.0/16
  serviceSubnet: 10.96.0.0/12
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  certSANs:
    - 127.0.0.1
    - localhost
    - 192.168.104.4
    - lima-control-plane-0.internal
controllerManager: {}
scheduler: {}
dns: {}
proxy: {}
EOF

sudo mv /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.old
sudo mv /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.old

sudo kubeadm init phase certs apiserver --config /tmp/kubeadm-clusterconfig.yaml
sudo systemctl restart kubelet
```