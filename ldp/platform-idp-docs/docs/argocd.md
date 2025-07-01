# Argo CD Integration

To use Argo CD as your GitOps engine:

1. **Git Repository**  
   Store your claim files in a Git repo, e.g., `git@github.com:your-org/platform-claims.git`.

2. **Directory Layout**  
   ```
   clusters/
     dev/
       apps/
         microservices/
           nginx-frontend.yaml
   ```

3. **Argo CD Application**  
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: microservices-dev
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: 'git@github.com:your-org/platform-claims.git'
       targetRevision: HEAD
       path: clusters/dev/apps
     destination:
       server: 'https://kubernetes.default.svc'
       namespace: apps
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
       - CreateNamespace=true
   ```

With this, any new claim placed under `clusters/dev/apps` is automatically synced by Argo CD and provisioned by Crossplane.
