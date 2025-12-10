# OIDC
## NB

- use http://localhost:8000 as redirect uri http://localhost:18000

```bash
kubectl create secret generic headlamp-oidc \
  --namespace headlamp \
  --from-literal=OIDC_CLIENT_ID=$OIDC_CLIENT_ID \
  --from-literal=OIDC_CLIENT_SECRET=$OIDC_CLIENT_SECRET \
  --from-literal=OIDC_ISSUER_URL=$OIDC_ISSUER_URL \
  --from-literal=OIDC_SCOPES=email,profile
```

```bash
  kubectl oidc-login setup \
  --oidc-issuer-url=$OIDC_ISSUER_URL \
  --oidc-client-id=$OIDC_CLIENT_ID \
  --oidc-client-secret=$OIDC_CLIENT_SECRET
```
### Create OIDC User for the Cluster.
```bash
kubectl config set-credentials authentik-oidc \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url=$OIDC_ISSUER_URL \
  --exec-arg=--oidc-client-id=$OIDC_CLIENT_ID \
  --exec-arg=--oidc-client-secret=OIDC_CLIENT_SECRET \
  --exec-arg=--oidc-extra-scope=email,profile
```
### Link the User to the Cluster
`kubectl config get-clusters` to get cluster names.
```bash
kubectl config set-context authentik-oidc --namespace=headlamp --cluster=kubernetes --user=authentik-oidc
kubectl config use-context authentik-oidc
```

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-oidc-admin
subjects:
- kind: User
  name: "codesenju@gmail.com"  # <<< Change this to the actual OIDC username!
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
```

# Reference:
- https://github.com/int128/kubelogin/blob/master/docs/setup.md