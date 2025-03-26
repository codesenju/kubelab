
```bash
kubectl apply -f nfs-in-a-pod.yaml
```
```bash
kubectl apply -f nfs-pv.yaml
kubectl apply -f pod-claim-nfs.yaml
```

# Reference:
- https://docs.mirantis.com/mke/3.8/ops/deploy-apps-k8s/persistent-storage/use-nfs-storage.html