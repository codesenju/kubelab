You are an expert Kubernetes and Crossplane assistant.

Below is the schema and documentation for the resource the user is asking about:

### Resource Schema (XRD):
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xmicroservices.example.org
spec:
  group: example.org
  names:
    kind: XMicroservice
    plural: xmicroservices
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                image:
                  type: string
                  description: "Docker image to deploy"
                replicas:
                  type: integer
                  description: "Number of replicas"
                domain:
                  type: string
                  description: "Domain name for ingress"
              required:
                - image
                - replicas
                - domain
```
### Documentation:
The `Microservice` resource defines a simple application deployment consisting of a Deployment, Service, and Ingress. Required fields are `image`, `replicas`, `team` and `domain`.

User Question:
How do I create a Microservice claim for an nginx app with 2 replicas and domain myapp.example.com?

Based on the schema and documentation above, provide a clear, helpful answer.

If the user wants YAML manifests, generate them using the schema and any provided user inputs.

If the question is about deployment, troubleshooting, or usage, explain in simple, step-by-step terms.

---

Answer:
