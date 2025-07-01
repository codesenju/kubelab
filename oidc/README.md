# ✅ Configuring `kubectl` with OpenID Connect (OIDC) via Authentik

## Prerequisites

- Kubernetes cluster (set up via `kubeadm`)
- Access to control plane
- Authentik running and reachable
- `kubectl` installed
- `krew` plugin manager installed

---

## 🔐 1. Create an OAuth2 Application in Authentik

1. Navigate to **Applications** > **Create**
2. Name: `Kubernetes`
3. Slug: `kubernetes`
4. Protocol: `OIDC`
5. Redirect URIs: `http://localhost:8000`
6. Authorization flow: `authorization-code`
7. Scopes:
   - `openid`
   - `profile`
   - `email`
   - `groups` (optional if using group-based RBAC)

📌 Save the:
- Client ID
- Client Secret
- Issuer URL (e.g., `https://auth.example.com/application/o/kubernetes/`)

---

## ⚙️ 2. Configure Kubernetes API Server for OIDC

Edit the API server manifest:

```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add the following flags:

```yaml
- --oidc-issuer-url=https://auth.example.com/application/o/kubernetes/
- --oidc-client-id=kubernetes
- --oidc-username-claim=email
- --oidc-groups-claim=groups
- --oidc-ca-file=/etc/kubernetes/pki/oidc-ca.crt
```

> Replace the URL and paths with your values. The CA file is required if you're using a self-signed certificate.

---

## 🔐 3. Create a ClusterRoleBinding

Use an environment variable for the user’s email:

```bash
export USER_EMAIL=you@example.com

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-cluster-admin
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: User
  name: \${USER_EMAIL}
  apiGroup: rbac.authorization.k8s.io
EOF
```

---

## 🔌 4. Install `kubectl krew` and `oidc-login`

### Install `krew` plugin manager:

```bash
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm64/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
```

Add `krew` to your `PATH`:

```bash
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
```

Then restart your terminal or run:

```bash
source ~/.zshrc  # or source ~/.bash_profile
```

### Install the `oidc-login` plugin:

```bash
kubectl krew install oidc-login
```

---

## ⚙️ 5. Configure `kubectl` Context

Edit your kubeconfig to add the OIDC user:

```yaml
users:
- name: oidc-user
  user:
    exec:
      apiVersion: "client.authentication.k8s.io/v1beta1"
      command: "kubectl"
      args:
        - "oidc-login"
        - "get-token"
        - "--oidc-issuer-url=https://auth.example.com/application/o/kubernetes/"
        - "--oidc-client-id=kubernetes"
        - "--oidc-client-secret=YOUR_CLIENT_SECRET"
        - "--oidc-extra-scope=email"
        - "--oidc-extra-scope=profile"
        - "--oidc-extra-scope=groups"
```

Set the context:

```bash
kubectl config set-context oidc-context --cluster=your-cluster --user=oidc-user
kubectl config use-context oidc-context
```

---

## ✅ Test Login

Run:

```bash
kubectl get nodes
```

You should be prompted to authenticate via browser and then receive a token to interact with the cluster.

# Troubleshooting

```bash
kubectl oidc-login get-token \
--oidc-issuer-url=$ISSUER_URL \
--oidc-client-id=$CLIENT_ID \
--oidc-client-secret=$CLIENT_SECRET | jq -r '.status.token'

```