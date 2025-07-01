```bash
kubectl create ns monitoring
kubectl -n monitoring create secret generic beszel-secret --from-literal=agent-key='YOUR-KEY-HERE'
```