# Troubleshooting Guide

This document provides solutions for common issues encountered when working with the Kubelab Kubernetes cluster.

## SSH Connection Issues

### Problem: SSH Permission Denied

```
k8s-worker-1 | UNREACHABLE! => {
    "changed": false,
    "msg": "Failed to connect to the host via ssh: Warning: Permanently added '192.168.0.51' (ED25519) to the list of known hosts.\r\nubuntu@192.168.x.xx: Permission denied (publickey,password).",
    "unreachable": true
}
```

### Solution:

Reset your SSH known hosts file:

```bash
mv ~/.ssh/known_hosts ~/.ssh/known_hosts.bkp
```

## Kubernetes Resource Issues

### Problem: CRDs Stuck in Terminating State

When custom resource definitions (CRDs) get stuck in the terminating state, they can block cluster operations.

### Solution:

Remove finalizers from the stuck CRDs:

```bash
# List all Longhorn CRDs
kubectl get crd | grep longhorn | awk '{print $1}'

# Remove finalizers from a specific CRD
kubectl patch crd backuptargets.longhorn.io -p '{"metadata":{"finalizers":[]}}' --type=merge
```

## ArgoCD Deployment Issues

### Problem: ArgoCD Pod Readiness Check Fails

```
TASK [Wait for ArgoCD pods to be ready] ***************************************************
An exception occurred during task execution. To see the full traceback, use -vvv. The error was: AttributeError: 'NoneType' object has no attribute 'status'
fatal: [k8s-control-plane-1]: FAILED! => {"changed": false, "module_stderr": "Shared connection to 192.168.0.41 closed.\r\n", "module_stdout": "Traceback (most recent call last):\r\n...
```

### Solution:

Try deploying ArgoCD again:

```bash
ansible-playbook ../addons/argocd.yaml
```

## Network Issues

### Problem: Services Not Accessible

If Kubernetes services are not accessible from outside the cluster, check the following:

### Solution:

1. Verify that the LoadBalancer or NodePort services have the correct configuration:

```bash
kubectl get svc -A
```

2. Check that the ingress controller is properly configured:

```bash
kubectl get ingress -A
```

3. Ensure firewall rules allow traffic to the service ports:

```bash
sudo ufw status
```

## Storage Issues

### Problem: PersistentVolumeClaims Stuck in Pending State

### Solution:

1. Check if the storage class exists and is set as default:

```bash
kubectl get sc
```

2. Verify that the NFS server is accessible:

```bash
showmount -e 192.168.0.15
```

3. Check the events for the PVC:

```bash
kubectl describe pvc <pvc-name>
```

## Application Deployment Issues

### Problem: ArgoCD Applications Out of Sync

### Solution:

1. Check the sync status:

```bash
kubectl get applications -n argocd
```

2. Force a sync:

```bash
kubectl annotate applications -n argocd <app-name> argocd.argoproj.io/refresh="hard" --overwrite
```

3. Verify that the Git repository is accessible and the branch references are correct.
