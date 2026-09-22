# Virtual Kubelet + containerd CRI on kubeadm (lab guide)

**Tested lab:** Ubuntu x86-64 VM `192.168.0.31`, kubeadm API `192.168.0.40:6443`, containerd 2.2.2, Go 1.18.1, Virtual Kubelet CRI source from 2019. **Assumption:** TCP **10250 is available** on the VM. Commands under **VM** run in a root shell (`sudo -i`); **admin** commands require a cluster-admin kubeconfig. For the easiest copy-and-paste path, have that admin kubeconfig available on the VM during initial setup; the provider itself uses a separate, restricted kubeconfig. Replace the example IPs, API endpoint, and free Pod CIDR for your environment.

> **Lab only.** The old CRI provider is not a drop-in kubeadm worker. Its CRI imports, Kubernetes dependencies and permissions needed patching. The example grants read access to *all Secrets within the disposable `cri-lab` namespace*. It does not establish cross-node Pod routing, Services/DNS, persistent-volume support, or production-grade kubelet serving TLS. The hostPort example exposes an HTTP test service on your LAN; do not use it for sensitive workloads. Do not grant the node cluster-admin permissions.

## 1. Enable containerd's CRI and install prerequisites — VM

```bash
sudo apt-get update
sudo apt-get install -y git golang-go openssl jq curl wget ca-certificates
sudo grep -n 'disabled_plugins' /etc/containerd/config.toml
```

If `cri` appears in `disabled_plugins`, edit `/etc/containerd/config.toml` to remove **only** that disabled plugin (for example, change `disabled_plugins = ["cri"]` to `disabled_plugins = []`). Then, in a maintenance window, restart the **shared** containerd service; this can affect running Docker workloads:

```bash
sudo systemctl restart containerd
# Install crictl if absent; choose the linux-amd64 release matching your architecture.
if ! command -v crictl >/dev/null; then
  curl -fL https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.37.0/crictl-v1.37.0-linux-amd64.tar.gz \
    | sudo tar -xz -C /usr/local/bin crictl
fi
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock version
```

**Validate:** CRI runtime reports API `v1`; Docker remains healthy (`docker ps`). If `crictl info` initially says `NetworkReady=false`, complete step 5 before testing Pods.

## 2. Patch and build the legacy provider for CRI v1 — VM

**Do not** run `go build -o virtual-kubelet .` at the repository root: that builds the library package, not the runnable CLI.

```bash
git clone https://github.com/virtual-kubelet/cri.git /opt/cri
cd /opt/cri
# Source used v1alpha2; containerd 2.2.2 exposes CRI v1.
sed -i 's#k8s.io/cri-api/pkg/apis/runtime/v1alpha2#k8s.io/cri-api/pkg/apis/runtime/v1#g' client.go cri.go
gofmt -w client.go cri.go

# Keep the replace: old Kubernetes dependencies request nonexistent cri-api v0.0.0.
go mod edit -require=k8s.io/cri-api@v0.23.0
go mod edit -replace=k8s.io/cri-api=k8s.io/cri-api@v0.23.0
go mod download k8s.io/cri-api
go mod tidy -compat=1.18
go list -m k8s.io/cri-api
go list k8s.io/cri-api/pkg/apis/runtime/v1
```

Patch the old `node-cli` dependency in a **local copy**. It creates an unauthorized `kubernetes.io/role` node label and its ConfigMap/Secret informers otherwise list cluster-wide. The CLI's default `opts.New()` is fine here because port **10250 is free**.

```bash
cd /opt/cri
MODDIR=$(go list -m -f '{{.Dir}}' github.com/virtual-kubelet/node-cli)
cp -a "$MODDIR" /opt/cri/local-node-cli
chmod -R u+w /opt/cri/local-node-cli
python3 - <<'PY'
from pathlib import Path
node = Path('/opt/cri/local-node-cli/internal/commands/root/node.go')
s = node.read_text()
old = '"kubernetes.io/role":     "agent",'
assert s.count(old) == 1, 'Node label location changed; inspect node.go'
node.write_text(s.replace(old, '', 1))

root = Path('/opt/cri/local-node-cli/internal/commands/root/root.go')
s = root.read_text()
old = 'scmInformerFactory := kubeinformers.NewSharedInformerFactoryWithOptions(client, c.InformerResyncPeriod)'
new = '''scmInformerFactory := kubeinformers.NewSharedInformerFactoryWithOptions(
    client, c.InformerResyncPeriod, kubeinformers.WithNamespace(c.KubeNamespace))'''
assert s.count(old) == 1, 'Informer code changed; inspect root.go'
root.write_text(s.replace(old, new, 1))
PY

gofmt -w local-node-cli/internal/commands/root/{node,root}.go
go mod edit -replace=github.com/virtual-kubelet/node-cli=/opt/cri/local-node-cli
mkdir -p bin
go build -o bin/virtual-kubelet-cri-v1 ./cmd/virtual-kubelet
file bin/virtual-kubelet-cri-v1
./bin/virtual-kubelet-cri-v1 --help
```

**Validate:** `go list` resolves `k8s.io/cri-api/pkg/apis/runtime/v1`, and `file` identifies the built CLI as an ELF executable. Build errors about missing `go.sum` entries: rerun `go mod tidy -compat=1.18`; avoid unrelated mass upgrades.

## 3. Give the virtual node its own client identity

**VM — generate a private key and CSR** (never share the key):

```bash
sudo install -d -m 700 /etc/virtual-kubelet
sudo openssl req -new -newkey rsa:2048 -nodes \
  -keyout /etc/virtual-kubelet/client.key \
  -out /etc/virtual-kubelet/client.csr \
  -subj '/CN=system:node:cri-lab/O=system:nodes'
sudo chmod 600 /etc/virtual-kubelet/client.key
```

**Admin — submit and approve the request.** The block assumes your admin `kubectl` is available on the VM. If admin access is only on another machine, copy just `/etc/virtual-kubelet/client.csr` there, submit it from that machine, and copy the signed certificate back. Never copy the private key off the VM.

```bash
kubectl delete csr cri-lab-client --ignore-not-found
CSR=$(base64 -w0 /etc/virtual-kubelet/client.csr)
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: cri-lab-client
spec:
  request: ${CSR}
  signerName: kubernetes.io/kube-apiserver-client
  usages: [client auth]
  expirationSeconds: 31536000
EOF
kubectl certificate approve cri-lab-client
kubectl get csr cri-lab-client
```

**VM, with admin `kubectl` still active — retrieve the issued certificate and cluster CA.** The CA extraction works when the admin kubeconfig embeds the CA data; if the CA is referenced by a file path, copy your kubeadm control plane's `/etc/kubernetes/pki/ca.crt` securely to `/etc/virtual-kubelet/ca.crt` instead. Do not use `--insecure-skip-tls-verify`.

```bash
kubectl get csr cri-lab-client -o jsonpath='{.status.certificate}' \
  | base64 -d > /etc/virtual-kubelet/client.crt
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > /etc/virtual-kubelet/ca.crt
openssl x509 -in /etc/virtual-kubelet/client.crt -noout -subject
openssl x509 -in /etc/virtual-kubelet/ca.crt -noout -subject
chmod 600 /etc/virtual-kubelet/client.key /etc/virtual-kubelet/client.crt
```

If `openssl` cannot read `ca.crt`, obtain the kubeadm CA from the control-plane host and rerun the CA check. **Now create the provider's dedicated kubeconfig:**

```bash
KCFG=/etc/virtual-kubelet/kubeconfig
kubectl config set-cluster kubelab --server=https://192.168.0.40:6443 \
  --certificate-authority=/etc/virtual-kubelet/ca.crt --embed-certs=true --kubeconfig="$KCFG"
kubectl config set-credentials cri-lab \
  --client-certificate=/etc/virtual-kubelet/client.crt \
  --client-key=/etc/virtual-kubelet/client.key --embed-certs=true --kubeconfig="$KCFG"
kubectl config set-context cri-lab --cluster=kubelab --user=cri-lab --kubeconfig="$KCFG"
kubectl config use-context cri-lab --kubeconfig="$KCFG"
chmod 600 "$KCFG" /etc/virtual-kubelet/client.key
kubectl --kubeconfig="$KCFG" auth whoami
```

**Validate:** username is `system:node:cri-lab`. Do **not** use your admin kubeconfig to run the provider. This lab reuses the client cert for the provider's HTTPS listener, matching the setup tested here; use a properly issued serving certificate for a hardened deployment.

## 4. Restrict the watch to a disposable namespace — admin

```bash
kubectl create namespace cri-lab --dry-run=client -o yaml | kubectl apply -f -
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: cri-provider-watch, namespace: cri-lab}
rules:
- apiGroups: [""]
  resources: [pods, secrets, configmaps, services]
  verbs: [get, list, watch]
- apiGroups: [""]
  resources: [events]
  verbs: [create, patch, update]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: cri-provider-watch, namespace: cri-lab}
subjects:
- kind: User
  name: system:node:cri-lab
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: cri-provider-watch
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl auth can-i list secrets -n cri-lab --as=system:node:cri-lab
```

**Validate:** `yes` in `cri-lab`. Keep this namespace free of sensitive Secrets; no cluster-wide Secret privileges are granted.

## 5. Install CNI and configure a non-overlapping test subnet — VM

Before choosing a subnet, check `ip -4 route` and `docker network ls -q | xargs -r docker network inspect --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}'`. The example `172.30.240.0/24` was free *in the tested VM*; change it if it conflicts with your LAN/VPN/Docker/other Pod networks.

```bash
cd /tmp
VERSION=v1.9.1
wget "https://github.com/containernetworking/plugins/releases/download/$VERSION/cni-plugins-linux-amd64-$VERSION.tgz"
echo "b98f74a0f8522f0a83867178729c1aa70f2158f90c45a2ca8fa791db1c76b303  cni-plugins-linux-amd64-$VERSION.tgz" | sha256sum -c -
sudo install -d -m 755 /opt/cni/bin /etc/cni/net.d
sudo tar -xzf "cni-plugins-linux-amd64-$VERSION.tgz" -C /opt/cni/bin
ls /opt/cni/bin/{bridge,host-local,portmap,loopback}

sudo tee /etc/cni/net.d/10-cri-lab.conflist >/dev/null <<'EOF'
{
  "cniVersion": "1.0.0",
  "name": "cri-lab",
  "plugins": [
    {
      "type": "bridge", "bridge": "cni-cri0", "isGateway": true, "ipMasq": true,
      "ipam": {
        "type": "host-local", "subnet": "172.30.240.0/24",
        "routes": [{"dst": "0.0.0.0/0"}]
      }
    },
    {"type": "portmap", "capabilities": {"portMappings": true}},
    {"type": "loopback"}
  ]
}
EOF
sudo crictl info | jq -r '.status.conditions[] | "\(.type)=\(.status) \(.message // "")"'
```

**Validate:** `RuntimeReady=true` **and** `NetworkReady=true`. A historical `failed to load cni during init` journal entry is not a current failure if `crictl info` now says Ready. Check status *before* considering a disruptive containerd restart.

## 6. Run Virtual Kubelet — VM

```bash
sudo ss -lntp | grep ':10250' || true  # Must be free for this guide.
sudo env \
  VKUBELET_POD_IP=192.168.0.31 \
  APISERVER_CERT_LOCATION=/etc/virtual-kubelet/client.crt \
  APISERVER_KEY_LOCATION=/etc/virtual-kubelet/client.key \
  /opt/cri/bin/virtual-kubelet-cri-v1 \
    --provider cri \
    --kubeconfig /etc/virtual-kubelet/kubeconfig \
    --nodename cri-lab \
    --namespace cri-lab \
    --metrics-addr 127.0.0.1:10256 \
    --log-level debug
```

Keep it running in the foreground. **Admin — validate** in another terminal:

```bash
kubectl get node cri-lab -o wide
kubectl get node cri-lab -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status} Port={.status.daemonEndpoints.kubeletEndpoint.port}{"\n"}'
kubectl describe node cri-lab | grep '^Taints:'
```

**Expected:** Ready, internal IP `192.168.0.31`, kubelet endpoint **10250**, and `virtual-kubelet.io/provider=cri:NoSchedule`. Keep that taint.

## 7. Test Pod: create → run → logs → complete — admin / VM

**Admin — manifest** (direct `nodeName` bypasses scheduling; no need to remove the taint):

```bash
cat >/tmp/cri-hello.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cri-hello
  namespace: cri-lab
spec:
  nodeName: cri-lab
  restartPolicy: Never
  automountServiceAccountToken: false
  containers:
  - name: hello
    image: docker.io/library/busybox:1.36
    command: ["/bin/sh", "-c"]
    args: ["echo 'Hello from Virtual Kubelet CRI'; sleep 30"]
EOF
kubectl apply -f /tmp/cri-hello.yaml
kubectl get pod cri-hello -n cri-lab -o wide -w
```

**Validate:** Pod receives an IP from the test subnet, briefly becomes `Running`, then `Completed` with exit code 0. In another terminal:

```bash
kubectl logs -n cri-lab cri-hello
kubectl get pod cri-hello -n cri-lab -o wide
# On the VM, inspect the actual containerd CRI resources:
sudo crictl pods                 # NOT 'crictl pods -a': that flag does not exist.
sudo crictl ps -a
CID=$(sudo crictl ps -a --name hello -q | head -n 1)
[ -n "$CID" ] && sudo crictl logs "$CID"
```

**Expected log:** `Hello from Virtual Kubelet CRI`. `kubectl logs` working confirms the API-server → virtual-kubelet log path, not merely direct CRI access. Clean up with `kubectl delete pod cri-hello -n cri-lab`.

## 8. Expose nginx on `192.168.0.31:18080` using `hostPort` (no Service or port-forward)

**VM:** The CNI config in step 5 already includes `portmap` with `portMappings: true`. If you created the bridge config *before* adding `portmap`, add it as shown in step 5 and create a **new** Pod: existing sandboxes do not acquire host-port mappings retroactively. Check `sudo crictl info | jq -r '.status.conditions[] | "\(.type)=\(.status)"'` and make sure `NetworkReady=true`. Choose a free host port (`18080` in this example). `hostPort` is a **Pod** setting, not a Kubernetes Service.

**Admin — deploy nginx on the virtual node:** Before applying, check that nothing else uses TCP port 18080 (`sudo ss -lntp | grep ":18080 " || true`). The CNI portmap creates NAT rules, so a successful mapping will **not** necessarily show up in `ss`.

```bash
cat > /tmp/cri-hostport.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cri-hostport
  namespace: cri-lab
spec:
  nodeName: cri-lab
  automountServiceAccountToken: false
  containers:
  - name: nginx
    image: docker.io/library/nginx:1.27-alpine
    ports:
    - name: http
      containerPort: 80
      hostPort: 18080
      protocol: TCP
EOF
kubectl apply -f /tmp/cri-hostport.yaml
kubectl get pod cri-hostport -n cri-lab -o wide
```

Wait for `Running`; then **VM — verify nginx, CRI mapping and local host access:**

```bash
POD_IP=$(kubectl -n cri-lab get pod cri-hostport -o jsonpath='{.status.podIP}')
echo "Pod IP: $POD_IP"
curl --connect-timeout 3 --max-time 8 "http://${POD_IP}:80/"
curl --connect-timeout 3 --max-time 8 http://192.168.0.31:18080/
SID=$(sudo crictl pods --name cri-hostport -q | head -n 1)
sudo crictl inspectp -o json "$SID" | jq '{portMappings: .info.config.port_mappings, network: .status.network}'
sudo iptables-save -t nat | grep '18080' || true
```

**Expected:** both `curl` commands return the nginx welcome page; CRI reports `host_port: 18080` → `container_port: 80`; CNI NAT rules DNAT traffic to the Pod IP. `ss` or `netstat` need **not** show a listener on `18080` because `portmap` uses NAT rules.

**VM — allow LAN traffic through Docker's default-DROP forwarding chain:** The tested VM runs Docker, which inserts `DOCKER-USER` ahead of its own forwarding rules. First check `sudo iptables -nvL FORWARD` and `sudo iptables -nvL DOCKER-USER`. If `FORWARD` defaults to `DROP` and LAN access fails while local access works, apply these **temporary, narrow** rules. Run them as one block while the nginx Pod is running:

```bash
POD_IP=$(kubectl -n cri-lab get pod cri-hostport -o jsonpath='{.status.podIP}')
: "${POD_IP:?Pod has no IP; stop and check kubectl get pod}"
sudo iptables -C DOCKER-USER -i eth0 -o cni-cri0 \
  -s 192.168.0.0/24 -d "$POD_IP" -p tcp --dport 80 \
  -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || \
  sudo iptables -I DOCKER-USER 1 -i eth0 -o cni-cri0 \
    -s 192.168.0.0/24 -d "$POD_IP" -p tcp --dport 80 \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -C DOCKER-USER -i cni-cri0 -o eth0 \
  -s "$POD_IP" -d 192.168.0.0/24 -p tcp --sport 80 \
  -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || \
  sudo iptables -I DOCKER-USER 2 -i cni-cri0 -o eth0 \
    -s "$POD_IP" -d 192.168.0.0/24 -p tcp --sport 80 \
    -m conntrack --ctstate ESTABLISHED -j ACCEPT
sudo iptables -nvL DOCKER-USER --line-numbers
```

**MacBook / other LAN client — validate:**

```bash
curl -v --connect-timeout 3 --max-time 8 http://192.168.0.31:18080/
```

**Expected:** `HTTP/1.1 200 OK` and nginx's welcome page. Forward-chain rules match **Pod port 80**, not host port 18080, because DNAT happens first. If this still times out, watch `sudo tcpdump -ni eth0 'tcp port 18080'` and `sudo tcpdump -ni cni-cri0 'tcp port 80'` while retrying. Do **not** set the whole `FORWARD` policy to `ACCEPT` or flush Docker's rules. These firewall rules are not persistent and use the current Pod IP; recreating the Pod may require updating them. The test does **not** prove a Kubernetes NodePort Service or cross-node Pod routing works.

**Clean up this test:** Run while the Pod still exists, so `$POD_IP` resolves to the correct address:

```bash
POD_IP=$(kubectl -n cri-lab get pod cri-hostport -o jsonpath='{.status.podIP}')
if [ -n "$POD_IP" ]; then
  sudo iptables -D DOCKER-USER -i eth0 -o cni-cri0 \
    -s 192.168.0.0/24 -d "$POD_IP" -p tcp --dport 80 \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  sudo iptables -D DOCKER-USER -i cni-cri0 -o eth0 \
    -s "$POD_IP" -d 192.168.0.0/24 -p tcp --sport 80 \
    -m conntrack --ctstate ESTABLISHED -j ACCEPT
fi
kubectl delete pod cri-hostport -n cri-lab
```

## Quick fixes from this build

| Symptom | Cause / fix |
|---|---|
| `unknown service runtime.v1alpha2.RuntimeService` | Old source imports CRI v1alpha2; use CRI v1 imports and module replacement in step 2. |
| `k8s.io/cri-api@v0.0.0: unknown revision` | Removing the old `replace` entirely exposes a nonexistent transitive dependency; **replace with v0.23.0**, don't just drop it. |
| Missing `go.sum` entries | Run `go mod tidy -compat=1.18` after pinning CRI API. |
| `nodes "cri-lab" ... not allowed to set ... kubernetes.io/role` | Remove that label from local `node-cli` copy. |
| Cluster-wide Secret/ConfigMap `forbidden` | Scope shared informers and run with `--namespace cri-lab`; bind the namespace-only Role. |
| `listen tcp :10250: bind: address already in use` | This guide assumes the port is free. If not, use another host/port and adjust the provider's CLI options/source and node endpoint accordingly. |
| `NetworkReady=false` | Install CNI binaries and create `/etc/cni/net.d/10-cri-lab.conflist`; then re-check `crictl info`. |
| `hostPort` works from VM, but MacBook times out | Check `portmap` DNAT and Docker’s default-DROP `FORWARD` chain. Use the narrowly scoped `DOCKER-USER` rules in step 8; verify from another LAN client. |

**Source:** [virtual-kubelet/cri](https://github.com/virtual-kubelet/cri), [node-cli v0.1.2](https://github.com/virtual-kubelet/node-cli/tree/v0.1.2), [CNI plugins](https://github.com/containernetworking/plugins/releases). This runbook documents the successful lab path, not a maintained upstream deployment procedure.
