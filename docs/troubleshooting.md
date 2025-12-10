# Troubleshooting Guide

## 🚨 Common Issues and Solutions

### Cluster Issues

**Nodes not Ready:**
```bash
# Check node status
kubectl get nodes -o wide

# Check kubelet logs
sudo journalctl -u kubelet -f

# Common fixes:
# 1. Restart kubelet
sudo systemctl restart kubelet

# 2. Check CNI pods
kubectl get pods -n kube-system -l k8s-app=cilium

# 3. Reset and rejoin node
sudo kubeadm reset
ansible-playbook main.yaml --vault-password-file ~/vault-password.txt --limit <node>
```

**Pod Networking Issues:**
```bash
# Test pod-to-pod connectivity
kubectl run test1 --image=busybox --rm -it --restart=Never -- sh
kubectl run test2 --image=busybox --rm -it --restart=Never -- sh

# Check CNI status
kubectl get pods -n kube-system
kubectl logs -n kube-system -l k8s-app=cilium

# Restart CNI if needed
kubectl delete pods -n kube-system -l k8s-app=cilium
```

### Application Deployment Issues

**ArgoCD Application Stuck:**
```bash
# Check application status
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# Common fixes:
# 1. Force sync
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"sync":{"syncStrategy":{"force":true}}}}'

# 2. Delete and recreate
kubectl delete application <app-name> -n argocd
ansible-playbook ../addons/<app>.yaml --vault-password-file ~/vault-password.txt

# 3. Check source repository
kubectl get application <app-name> -n argocd -o yaml | grep repoURL
```

**Pods Stuck in Pending:**
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Common causes and fixes:
# 1. Resource constraints
kubectl top nodes
kubectl describe nodes

# 2. Storage issues
kubectl get pvc -A
kubectl get storageclass

# 3. Node selector/affinity
kubectl get nodes --show-labels
```

**Pods Crash Looping:**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check resource limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Limits\|Requests"

# Check liveness/readiness probes
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Liveness\|Readiness"
```

### Storage Issues

**PVC Stuck in Pending:**
```bash
# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass
kubectl describe storageclass <storage-class>

# Check provisioner logs
kubectl logs -n <provisioner-namespace> <provisioner-pod>

# For Longhorn:
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# For NFS:
kubectl get pods -n kube-system -l app=csi-nfs-controller
```

**Storage Performance Issues:**
```bash
# Test storage performance
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: storage-test
spec:
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'dd if=/dev/zero of=/data/test bs=1M count=1000; sync']
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: <pvc-name>
EOF

# Monitor I/O
kubectl exec storage-test -- iostat -x 1
```

### Networking Issues

**Ingress Not Working:**
```bash
# Check ingress controller
kubectl get pods -n traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Check ingress resources
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>

# Test internal service
kubectl run debug --image=busybox --rm -it --restart=Never -- sh
# Inside pod: wget -qO- http://<service>.<namespace>.svc.cluster.local
```

**DNS Resolution Issues:**
```bash
# Test DNS from pod
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check DNS configuration
kubectl get configmap -n kube-system coredns -o yaml
```

**Load Balancer Issues:**
```bash
# Check MetalLB (if used)
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l app=metallb

# Check IP pool configuration
kubectl get ipaddresspools -n metallb-system

# Test external connectivity
curl -v http://<external-ip>
```

### Security Issues

**RBAC Permission Denied:**
```bash
# Check current permissions
kubectl auth can-i <verb> <resource> --as=<user>

# Check role bindings
kubectl get rolebindings,clusterrolebindings -A | grep <user>

# Describe specific RBAC
kubectl describe clusterrole <role-name>
kubectl describe clusterrolebinding <binding-name>
```

**Certificate Issues:**
```bash
# Check cert-manager
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager

# Check certificates
kubectl get certificates -A
kubectl describe certificate <cert-name> -n <namespace>

# Check certificate requests
kubectl get certificaterequests -A
kubectl describe certificaterequest <request-name> -n <namespace>

# Force certificate renewal
kubectl delete certificate <cert-name> -n <namespace>
```

### Observability Issues

**Prometheus Not Scraping:**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets

# Check ServiceMonitor resources
kubectl get servicemonitors -A

# Check Prometheus configuration
kubectl get prometheus -n monitoring -o yaml
```

**Grafana Dashboard Issues:**
```bash
# Check Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Check data source configuration
kubectl port-forward -n monitoring svc/grafana 3000:80
# Login and check Configuration > Data Sources

# Test data source connectivity
# In Grafana: Data Sources > Test
```

**Tracing Not Working:**
```bash
# Check Tempo
kubectl get pods -n grafana-system -l app.kubernetes.io/name=tempo
kubectl logs -n grafana-system -l app.kubernetes.io/component=distributor

# Check OpenTelemetry collector
kubectl get pods -n obi-system
kubectl logs -n obi-system deployment/obi

# Test trace ingestion
kubectl port-forward -n grafana-system svc/tempo-distributor 14268:14268
curl -X POST http://localhost:14268/api/traces -d '{"spans":[{"traceID":"test"}]}'
```

## 🔧 Diagnostic Commands

### Cluster Health Check
```bash
#!/bin/bash
echo "=== Cluster Health Check ==="

echo "Nodes:"
kubectl get nodes -o wide

echo -e "\nSystem Pods:"
kubectl get pods -n kube-system

echo -e "\nResource Usage:"
kubectl top nodes
kubectl top pods -A --sort-by=cpu

echo -e "\nStorage:"
kubectl get pv,pvc -A

echo -e "\nIngress:"
kubectl get ingress -A

echo -e "\nApplications:"
kubectl get applications -n argocd
```

### Application Debug
```bash
#!/bin/bash
APP_NAME=$1
NAMESPACE=$2

echo "=== Debugging $APP_NAME in $NAMESPACE ==="

echo "Pods:"
kubectl get pods -n $NAMESPACE -l app=$APP_NAME

echo -e "\nPod Details:"
kubectl describe pods -n $NAMESPACE -l app=$APP_NAME

echo -e "\nLogs:"
kubectl logs -n $NAMESPACE -l app=$APP_NAME --tail=50

echo -e "\nEvents:"
kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp
```

### Network Debug
```bash
#!/bin/bash
echo "=== Network Diagnostics ==="

echo "CNI Pods:"
kubectl get pods -n kube-system -l k8s-app=cilium

echo -e "\nIngress Controllers:"
kubectl get pods -n traefik

echo -e "\nServices:"
kubectl get svc -A | grep -v ClusterIP

echo -e "\nEndpoints:"
kubectl get endpoints -A

echo -e "\nNetwork Policies:"
kubectl get networkpolicies -A
```

## 📊 Performance Monitoring

### Resource Monitoring
```bash
# Continuous monitoring
watch kubectl top nodes
watch kubectl top pods -A

# Resource usage over time
kubectl get --raw /metrics | grep node_cpu
kubectl get --raw /metrics | grep node_memory
```

### Application Performance
```bash
# Check application metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Useful queries:
# - rate(container_cpu_usage_seconds_total[5m])
# - container_memory_usage_bytes
# - kube_pod_container_status_restarts_total
```

## 🆘 Emergency Procedures

### Cluster Recovery
```bash
# If control plane is down:
# 1. Check etcd health
sudo systemctl status etcd

# 2. Restore from backup (if available)
sudo kubeadm init phase etcd local --config=kubeadm-config.yaml

# 3. Rejoin nodes
ansible-playbook main.yaml --vault-password-file ~/vault-password.txt --tags k8s
```

### Application Recovery
```bash
# Force delete stuck resources
kubectl delete <resource> <name> --grace-period=0 --force

# Reset ArgoCD application
kubectl patch application <app-name> -n argocd --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl delete application <app-name> -n argocd

# Redeploy from scratch
ansible-playbook ../addons/<app>.yaml --vault-password-file ~/vault-password.txt
```

---

**🚨 Emergency Contact:** For critical issues, check the GitHub issues page or create a new issue with detailed logs and error messages.
