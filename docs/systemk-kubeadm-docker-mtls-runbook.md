# Systemk Virtual Kubelet on kubeadm + Docker mTLS

A compact runbook for the tested homelab setup. **Systemk runs Linux processes as systemd units, not OCI containers.** We additionally run the Docker *CLI* inside a Systemk-managed unit to talk to the host Docker Engine over mutual TLS. Kubernetes manages the CLI/unit, **not** the Docker container's lifecycle.

## Environment

| Component | Value |
|---|---|
| Kubernetes | kubeadm control-plane endpoint `192.168.0.40:6443` (cluster observed at v1.35.8) |
| Ubuntu VM | `192.168.0.31`, Ubuntu 22.04 |
| Virtual node | `systemk` (reports v1.18.15; experimental/version-skew unsupported) |
| Systemk binary | `/usr/local/bin/systemk` |
| Node kubeconfig | `/etc/systemk/kubeconfig` |
| Systemk HTTPS endpoint | `192.168.0.31:10250` |
| Docker mTLS proxy | `127.0.0.1:2376` → `/run/docker.sock` |

Commands marked **control-plane** run on a kubeadm control-plane VM; commands marked **admin** run on your MacBook/other host with administrator `kubectl`; **Ubuntu** commands run on `192.168.0.31`. Replace usernames and paths as necessary.

> **Security:** The original Systemk README's test flow copies the **Kubernetes root CA private key** into a `cert-manager` Secret and creates a broadly privileged node role binding. This is **lab-only**: possession of the cluster CA key can compromise cluster identity. Prefer a dedicated node CSR approval/signing process and least-privilege authorization in a real deployment. Do not publish the CA key, kubeconfig, or Docker client/server keys. The root-CA step below records what we used, not a recommended production design.

## 1. Create Systemk node credentials

If cert-manager is already installed, **do not reinstall an old version from the repository's README**.

**Control-plane:** create the lab-only CA Secret (skip if already created):

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  -n cert-manager create secret tls priv-ca \
  --cert=/etc/kubernetes/pki/ca.crt \
  --key=/etc/kubernetes/pki/ca.key
```

**Admin:** issuer, certificate, and RBAC. The node certificate's Common Name must match the name Systemk registers.

```bash
export NODENAME=systemk
kubectl apply -f - <<'EOF_ISSUER'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: priv-ca-issuer
spec:
  ca:
    secretName: priv-ca
EOF_ISSUER
kubectl wait --for=condition=Ready --timeout=60s clusterissuer/priv-ca-issuer

cat <<EOF_CERT | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${NODENAME}
  namespace: default
spec:
  secretName: ${NODENAME}-tls
  duration: 8760h
  renewBefore: 4380h
  subject:
    organizations: [system:nodes]
  commonName: system:node:${NODENAME}
  issuerRef:
    name: priv-ca-issuer
    kind: ClusterIssuer
EOF_CERT
kubectl wait --for=condition=Ready --timeout=60s certificate/systemk

# Original repository's broad, LAB-ONLY RBAC (may report AlreadyExists on rerun):
kubectl create clusterrolebinding systemk-view \
  --clusterrole=system:node --user=system:node:systemk
```

**Admin:** create a *dedicated* kubeconfig for Systemk, without copying `admin.conf` or its administrator client credentials. The following assumes your current admin kubeconfig embeds the CA certificate; if it uses a file path, copy that **public** CA certificate instead.

```bash
umask 077
kubectl -n default get secret systemk-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > systemk.crt
kubectl -n default get secret systemk-tls -o jsonpath='{.data.tls\.key}' | base64 -d > systemk.key
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > kubeadm-ca.crt

KCFG="$PWD/systemk.kubeconfig"
kubectl --kubeconfig="$KCFG" config set-cluster kubeadm \
  --server=https://192.168.0.40:6443 \
  --certificate-authority="$PWD/kubeadm-ca.crt" --embed-certs=true
kubectl --kubeconfig="$KCFG" config set-credentials systemk \
  --client-certificate="$PWD/systemk.crt" --client-key="$PWD/systemk.key" --embed-certs=true
kubectl --kubeconfig="$KCFG" config set-context systemk --cluster=kubeadm --user=systemk
kubectl --kubeconfig="$KCFG" config use-context systemk
chmod 600 "$KCFG"
scp "$KCFG" ubuntu@192.168.0.31:/tmp/systemk.kubeconfig
```

**Ubuntu:**

```bash
sudo install -d -m 700 /etc/systemk
sudo mv /tmp/systemk.kubeconfig /etc/systemk/kubeconfig
sudo chown root:root /etc/systemk/kubeconfig
sudo chmod 600 /etc/systemk/kubeconfig
sudo kubectl --kubeconfig=/etc/systemk/kubeconfig auth whoami
# Expected username: system:node:systemk
```

## 2. Build Systemk on Ubuntu

```bash
sudo apt update
sudo apt install -y git golang-go build-essential pkg-config libsystemd-dev
cd /home/ubuntu
git clone https://github.com/virtual-kubelet/systemk.git
cd systemk
CGO_ENABLED=1 go build -o systemk .
./systemk --help
sudo install -m 755 systemk /usr/local/bin/systemk
```

> The installed build uses **`--internal-ip`**, not the `--node-ip` flag mentioned in older documentation. Systemk requires root to manage systemd units and mounts.

## 3. TLS for Systemk's kubelet-compatible log endpoint

This **server** certificate is separate from Systemk's **client** kubeconfig and Docker mTLS certificates. **Ubuntu:**

```bash
sudo install -d -m 700 /etc/systemk/tls
sudo openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
  -keyout /etc/systemk/tls/server.key -out /etc/systemk/tls/server.crt \
  -subj '/CN=systemk' \
  -addext 'subjectAltName=DNS:systemk,IP:192.168.0.31'
sudo chmod 600 /etc/systemk/tls/server.key
sudo chmod 644 /etc/systemk/tls/server.crt
```

For a one-time foreground test, run as root:

```bash
sudo /usr/local/bin/systemk \
  --kubeconfig=/etc/systemk/kubeconfig --nodename=systemk \
  --internal-ip=192.168.0.31 \
  --tls-cert=/etc/systemk/tls/server.crt \
  --tls-key=/etc/systemk/tls/server.key
```

## 4. Run Systemk as a systemd service

Stop the foreground Systemk instance with Ctrl+C **before** starting a second instance. **Ubuntu:**

```bash
sudo tee /etc/systemd/system/systemk.service >/dev/null <<'EOF_SERVICE'
[Unit]
Description=Systemk Virtual Kubelet
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/systemk --kubeconfig=/etc/systemk/kubeconfig --nodename=systemk --internal-ip=192.168.0.31 --tls-cert=/etc/systemk/tls/server.crt --tls-key=/etc/systemk/tls/server.key
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/systemk.service
sudo systemctl enable --now systemk.service
sudo systemctl status systemk --no-pager -l
sudo ss -lntp | grep ':10250'
```

**Admin:**

```bash
kubectl get node systemk -o wide     # Expected: Ready, InternalIP 192.168.0.31
kubectl get pods -A --field-selector spec.nodeName=systemk -o wide
```

**Isolate the test node:** avoid letting ordinary DaemonSets/CSI agents run as native systemd services. Cordon it and apply a dedicated taint; explicit `nodeName: systemk` test Pods still bypass the scheduler's `NoSchedule` check. A taint/cordon does *not* remove existing Pods or necessarily exclude DaemonSets with tolerations.

```bash
kubectl cordon systemk
kubectl taint node systemk virtual-kubelet.io/provider=systemk:NoSchedule
kubectl get pods -A --field-selector spec.nodeName=systemk -o wide
```

## 5. Configure Docker API mutual TLS without restarting Docker

The host Docker Engine continues listening on its Unix socket. We use **socat** to terminate mTLS on *loopback only* at `127.0.0.1:2376` and forward to `/run/docker.sock`. This avoids editing `dockerd`'s `-H fd://` systemd configuration and restarting the existing daemon.

**Ubuntu (root shell):**

```bash
sudo -i
apt install -y socat openssl
install -d -m 700 /root/docker-mtls-ca /etc/docker-mtls /etc/systemk/docker-client
cd /root/docker-mtls-ca
umask 077

# Dedicated CA (never use kubeadm's CA here)
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 3650 -sha256 -key ca-key.pem -out ca.pem \
  -subj '/CN=Kubelab Docker CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign'

# Server identity, valid for loopback and the VM IP
openssl genrsa -out server-key.pem 3072
openssl req -new -key server-key.pem -out server.csr -subj '/CN=ubuntu-docker'
cat > server-ext.cnf <<'EOF_SERVER'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:ubuntu-docker,IP:127.0.0.1,IP:192.168.0.31
EOF_SERVER
openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile server-ext.cnf

# Client identity for Systemk
openssl genrsa -out systemk-key.pem 3072
openssl req -new -key systemk-key.pem -out systemk.csr -subj '/CN=systemk-docker-client'
cat > client-ext.cnf <<'EOF_CLIENT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
EOF_CLIENT
openssl x509 -req -days 365 -sha256 -in systemk.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out systemk-cert.pem -extfile client-ext.cnf

openssl verify -CAfile ca.pem -purpose sslserver server-cert.pem
openssl verify -CAfile ca.pem -purpose sslclient systemk-cert.pem

install -m 644 ca.pem /etc/docker-mtls/ca.pem
install -m 644 server-cert.pem /etc/docker-mtls/server-cert.pem
install -m 600 server-key.pem /etc/docker-mtls/server-key.pem
install -m 644 ca.pem /etc/systemk/docker-client/ca.pem
install -m 644 systemk-cert.pem /etc/systemk/docker-client/cert.pem
install -m 600 systemk-key.pem /etc/systemk/docker-client/key.pem
```

Create the proxy service, still on **Ubuntu**:

```bash
cat > /etc/systemd/system/docker-mtls-proxy.service <<'EOF_PROXY'
[Unit]
Description=Docker Engine mutual TLS API proxy
Requires=docker.socket
After=docker.socket

[Service]
Type=simple
ExecStart=/usr/bin/socat -d -d OPENSSL-LISTEN:2376,bind=127.0.0.1,reuseaddr,fork,verify=1,cert=/etc/docker-mtls/server-cert.pem,key=/etc/docker-mtls/server-key.pem,cafile=/etc/docker-mtls/ca.pem UNIX-CONNECT:/run/docker.sock
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_PROXY
systemctl daemon-reload
systemctl enable --now docker-mtls-proxy.service
systemctl status docker-mtls-proxy --no-pager -l
ss -lntp | grep ':2376'
```

**Compatibility fix we encountered:** Ubuntu's installed socat rejected `min-proto-version=TLS1.2` with `unknown option`. The working command above **omits** it; TLS protocol minimum therefore depends on your OpenSSL/socat configuration. Do not claim a particular minimum until separately tested/enforced.

### Verify mTLS (Ubuntu)

```bash
# Authenticated client must return OK:
curl --fail --show-error \
  --cacert /etc/systemk/docker-client/ca.pem \
  --cert /etc/systemk/docker-client/cert.pem \
  --key /etc/systemk/docker-client/key.pem \
  https://127.0.0.1:2376/_ping

# Unauthenticated client MUST fail (observed: TLSv1.3 'certificate required'):
curl --show-error --cacert /etc/systemk/docker-client/ca.pem \
  https://127.0.0.1:2376/_ping

# Docker CLI with verified TLS should list existing containers:
DOCKER_HOST=tcp://127.0.0.1:2376 \
DOCKER_TLS_VERIFY=1 \
DOCKER_CERT_PATH=/etc/systemk/docker-client \
  docker ps
```

After the mTLS path is proven, stop the **old unauthenticated** port-2375 socat proxy (if created as a service):

```bash
systemctl disable --now docker-tcp-proxy.service   # if this unit exists
ss -lntp | grep -E ':2375|:2376'              # only 127.0.0.1:2376 should listen
```

If the old proxy was started manually, stop **that** foreground process; don't stop the new port-2376 proxy. Binding to loopback reduces network exposure but **any local process able to reach 2376 with a valid client key has root-equivalent Docker control**. Restrict the key and keep the CA private key offline after issuance.

## 6. Test Pod manifests

**Admin:** the first Pod verifies native systemd execution and log retrieval; the second verifies Docker over mTLS. Systemk's `image: /bin/bash` or `image: /usr/bin/docker` refers to a **host executable**, not a Docker image. No image pulling is performed by Systemk.

### A. Native Bash Pod (`systemk-persistent.yaml`)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: systemk-persistent
spec:
  nodeName: systemk
  hostNetwork: true
  automountServiceAccountToken: false
  containers:
    - name: test
      image: /bin/bash
      command: [/bin/bash, -c]
      args:
        - |
          while true; do
            echo "Systemk is running on $(hostname)"
            sleep 10
          done
```

```bash
kubectl apply -f systemk-persistent.yaml
kubectl get pod systemk-persistent -o wide
kubectl logs -f systemk-persistent
# Ubuntu: sudo systemctl list-units --all 'systemk*'
# Ubuntu: sudo journalctl -u systemk.default.systemk-persistent.test.service -f
```

### B. Docker hello-world over mTLS (`systemk-docker-mtls.yaml`)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: systemk-docker-mtls
spec:
  nodeName: systemk
  hostNetwork: true
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
    - name: docker
      image: /usr/bin/docker
      env:
        - name: DOCKER_HOST
          value: tcp://127.0.0.1:2376
        - name: DOCKER_TLS_VERIFY
          value: "1"
        - name: DOCKER_CERT_PATH
          value: /etc/systemk/docker-client
        - name: NO_PROXY
          value: 127.0.0.1,localhost
        - name: no_proxy
          value: 127.0.0.1,localhost
      command: [/usr/bin/docker]
      args: [run, --rm, hello-world]
```

```bash
kubectl apply -f systemk-docker-mtls.yaml
kubectl get pod systemk-docker-mtls -o wide
kubectl logs systemk-docker-mtls
# Expected: 'Hello from Docker!' and eventual Pod phase Succeeded.
```

The Docker client certificate directory at `/etc/systemk/docker-client` was accessible to the tested Systemk unit; no `hostPath` socket mount or `TemporaryFileSystem=` override was required for the mTLS test.

## 7. Quick validation and troubleshooting

```bash
# Admin — virtual node and workloads
kubectl get node systemk -o wide
kubectl get pods -A --field-selector spec.nodeName=systemk -o wide
kubectl describe node systemk
kubectl logs systemk-persistent --tail=10

# Ubuntu — services and endpoints
sudo systemctl is-enabled systemk docker-mtls-proxy
sudo systemctl status systemk docker-mtls-proxy --no-pager -l
sudo ss -lntp | grep -E ':10250|:2375|:2376'
sudo journalctl -u systemk -n 100 --no-pager
sudo journalctl -u docker-mtls-proxy -n 50 --no-pager
```

- `kubectl logs` connection refused at `:10250`: check Systemk is running with `--tls-cert`/`--tls-key` and the port is reachable from the API server. A self-signed test cert may require `kubectl logs --insecure-skip-tls-verify-backend=true`; in this homelab, ordinary `kubectl logs` subsequently worked.
- `permission denied` reading `/etc/systemk/kubeconfig`: start Systemk as **root**; do not loosen the kubeconfig permissions.
- `unknown flag --node-ip`: use **`--internal-ip`** with this Systemk build.
- `docker.sock: no such file`: Systemk's default `TemporaryFileSystem=/var /run` hides the host socket. Use the tested mTLS TCP endpoint rather than a socket mount or broad filesystem override.
- `kubectl top node` shows `<unknown>` for `systemk`: this build does not provide verified compatible resource metrics to Metrics Server; node readiness and Pod execution can still work. Do not mistake it for zero usage.
- Systemk reports `v1.18.15` against kubeadm `v1.35.8`: **unsupported version skew**; keep the integration experimental, isolated, and backed up.

### References

- [Virtual Kubelet — core project](https://github.com/virtual-kubelet/virtual-kubelet) — provider architecture and interfaces.
- [Systemk — systemd provider](https://github.com/virtual-kubelet/systemk) — the provider used in this runbook; see its README for the original node-authentication and systemd examples.
- [Docker: Protect the daemon socket](https://docs.docker.com/engine/security/protect-access/) — CA and server/client certificates, `DOCKER_HOST`, and mutual TLS security.
- [cert-manager CA Issuer](https://cert-manager.io/docs/configuration/ca/) — how CA-based issuers use Kubernetes Secrets; avoid reusing the Kubernetes control-plane CA outside an isolated lab.
- [systemd.exec reference](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html) — `TemporaryFileSystem=`, `BindPaths=`, and filesystem namespacing relevant to Systemk.
- [socat manual](http://www.dest-unreach.org/socat/doc/socat.html) — `OPENSSL-LISTEN`, certificate verification, and Unix-socket forwarding. Supported flags vary by installed version.
