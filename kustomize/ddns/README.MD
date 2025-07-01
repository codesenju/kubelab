## Prerequisites:

Create namespace
```bash
kubectl create ns ddns
```
Create Secret
```bash
kubectl create secret generic cloudflare-api-secret --from-literal=CLOUDFLARE_API_TOKEN='YOUR_TOKEN' -n ddns
```
Create ConfigMap
```bash
kubectl create configmap cloudflare-config --from-literal=DOMAINS='example.org' --from-literal=PROXIED='false' --from-literal=IP6_PROVIDER='none' -n ddns
```