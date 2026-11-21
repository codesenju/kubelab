# Platform services

These are the Argo CD applications that make up the platform, grouped by area. Namespaces and delivery method are read from Argo CD on 2026-11-21. Live sync and health are shown in the catalog, not here.

## Observability

| Application | Purpose | Namespace | Delivery |
|---|---|---|---|
| signoz | Traces, metrics and logs | signoz | Helm |
| signoz-k8s-infra |  | signoz | Helm |
| signoz-mcp |  | signoz | Kustomize |
| otel-collector | OpenTelemetry collector | otel-system | Kustomize |
| opentelemetry-operator |  | opentelemetry-operator-system | Helm |
| kube-prometheus-stack | Prometheus and Grafana | kube-prometheus-stack | Helm |
| beszel | Host monitoring hub | beszel | Kustomize |
| beszel-agent |  | beszel | Kustomize |

## Security

| Application | Purpose | Namespace | Delivery |
|---|---|---|---|
| openbao | Secrets store | zero-trust | Helm |
| openbao-transit | Auto-unseal for OpenBao | zero-trust | Kustomize |
| vaultwarden | Password manager | zero-trust | Kustomize |
| crowdsec | Intrusion detection | crowdsec | Helm |
| cert-manager | Certificates | cert-manager | Helm |
| registry-creds |  | registry-creds | Kustomize |
| reflector |  | reflector | Helm |

## Storage and databases

| Application | Purpose | Namespace | Delivery |
|---|---|---|---|
| csi-truenas | TrueNAS CSI driver | csi-truenas | Kustomize |
| csi-driver-nfs |  | csi-driver-nfs | Helm |
| external-snapshotter |  | external-snapshotter | Kustomize |
| cloudnative-postgresql | PostgreSQL operator | cnpg-system | Helm |
| plugin-barman-cloud |  | cnpg-system | Helm |
| rustfs | S3-compatible object storage | rustfs | Kustomize |
| databasus | Database backups | databasus | Kustomize |

## Platform

| Application | Purpose | Namespace | Delivery |
|---|---|---|---|
| traefik | Ingress and Gateway API | traefik | Helm |
| traefik-crds |  | traefik | Helm |
| metrics-server | Resource metrics API | kube-system | Helm |
| crossplane | Infrastructure composition | crossplane-system | Helm |
| kro | Resource graph definitions | kro | Helm |
| kro-rgd |  | kro | Kustomize |
| gitlab-runner | CI runners | gitlab | Helm |
| nexus | Artifact registry | nexus | Kustomize |
| coder | Developer workspaces | coder | Helm |
| backstage | This developer portal | backstage | Kustomize |
