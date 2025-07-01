# Platform IDP Documentation

This repository contains the definitions and usage examples for Crossplane-based Internal Developer Platform resources.

## Contents

- **xrd/**: Composite Resource Definitions (XRDs) and their schemas.
- **examples/**: Sample Claims demonstrating how to request resources.
- **templates/**: Template files (YAML/JSON) for generating new claims.
- **docs/**: Readme-style explanations for each resource and ArgoCD integration.

## GitOps with Argo CD

- Store your claim files under a Git repository that Argo CD watches.
- Organize claims under paths like `clusters/dev/apps/`.
- Configure an Argo CD `Application` to sync from that path to the `apps` namespace.
- Argo CD will reconcile any new or updated claims, triggering Crossplane to provision or update resources.
