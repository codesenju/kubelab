# How changes reach the cluster

## GitOps flow

1. Manifests live in the public `kubelab` repository under `kustomize/` and `addons/`.
2. An Ansible add-on playbook creates the Argo CD Application for each service. Values that must not be in Git are injected into the Application as parameters.
3. Argo CD syncs from `main` automatically, with prune and self-heal on for most applications.

## Rules for contributors

- Do not commit credentials, public IP addresses or personal domain names. A pre-commit hook blocks them. Do not bypass it.
- Kubernetes Secrets are created by Ansible tasks that read environment variables. Do not use a kustomize `secretGenerator` and do not commit `.env` files.
- Container images are deployed by digest, not by a floating tag.
- Change the digest in the live Argo CD Application and in the playbook in the same pull request, so a playbook run does not roll the image back.

## Backstage

- Catalog entities are shipped as a generated ConfigMap mounted at `/catalog`. Editing the files in `kustomize/backstage/base/catalog/` restarts the pod with the new content.
- Sign-in uses Authentik. A sign-in works only if a catalog User has the same email as the Authentik account.
- The private User entities come from a Secret created by the Backstage playbook, not from Git.

## Refreshing the hardware figures

Re-run the read-only collection over SSH on each Proxmox node, then update the tables in `infrastructure/`. The commands are `lscpu`, `free -b`, `dmidecode -s` and `dmidecode -t memory`, `lsblk -d`, `pvesm status`, and the link speed in `/sys/class/net/*/speed`.
