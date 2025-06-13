# Calico
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/tigera-operator.yaml

kubectl apply -f custom-resource.yaml
```

# Cilium
```bash
helm install cilium cilium/cilium --version 1.17.4 \
  --namespace kube-system
```