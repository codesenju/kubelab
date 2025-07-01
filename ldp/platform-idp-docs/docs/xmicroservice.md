# XMicroservice

**XMicroservice** is a Crossplane CompositeResourceDefinition (XRD) exposing a simple API to developers.

## Spec Fields

- **name** (string, required): Name of the microservice.
- **image** (string, required): Container image (e.g., `nginx:latest`).
- **domain** (string, required): Hostname for Ingress routing.
- **port** (integer, optional, default `80`): Port exposed by the Service.

Developers create a **Microservice** claim:

```yaml
apiVersion: platform.example.org/v1alpha1
kind: Microservice
metadata:
  name: my-app
spec:
  name: my-app
  image: nginx:1.25
  domain: my-app.example.com
  # port: 8080
```
