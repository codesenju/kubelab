## Table of Contents

- [Update existing secret](#update-existing-secret)
- [Create new secret](#create-new-secret)

## Update existing secret
```bash
kubectl create secret generic instagram-cookies \
  --from-file=cookies.txt=./cookies.txt \
  --dry-run=client -o yaml |
kubectl apply --server-side --force-conflicts -f -
```
## Create new secret
```
kubectl create secret generic instagram-cookies \
  --namespace=n8n \
  --from-file=cookies.txt=./cookies.txt
```
