# Trivy VEX + OTLP Publishing

This directory focuses on scanning container images with Trivy, applying VEX data from upstream, and publishing results as OTLP logs.

## Prerequisites

- `trivy`
- `jq`
- `curl`

## VEX source (direct internet)

The script uses Trivy CLI defaults for VEX repository resolution (`--vex repo`) and does not require a custom VEX repo URL flag.

## Scan with Trivy (manual)

```bash
export IMAGE="nginx:1.27-alpine"

trivy image \
  --scanners vuln \
  --vex repo \
  --db-repository "registry.local.jazziro.com/ghcrio/aquasecurity/trivy-db:2" \
  --java-db-repository "registry.local.jazziro.com/ghcrio/aquasecurity/trivy-java-db:1" \
  "$IMAGE"
```

## Verify DB proxy repos

```bash
TMP_CACHE="$(mktemp -d)"
trivy image --download-db-only \
  --cache-dir "$TMP_CACHE" \
  --db-repository "registry.local.jazziro.com/ghcrio/aquasecurity/trivy-db:2"
rm -rf "$TMP_CACHE"

TMP_CACHE="$(mktemp -d)"
trivy image --download-java-db-only \
  --cache-dir "$TMP_CACHE" \
  --java-db-repository "registry.local.jazziro.com/ghcrio/aquasecurity/trivy-java-db:1"
rm -rf "$TMP_CACHE"
```

If both commands end with `Artifact successfully downloaded`, your proxy mirror is working.

## Publish Trivy results to OTLP

Use the helper script:

```bash
IMAGE="nginx:1.27-alpine" \
OTLP_LOGS_URL="http://localhost:4318/v1/logs" \
./publish-trivy-otlp.sh
```

SigNoz collector example:

```bash
IMAGE="nginx:1.27-alpine" OTLP_LOGS_URL="https://signoz-otel-collector.local.jazziro.com/v1/logs" ./publish-trivy-otlp.sh
```

Note: if you pipe output to `pbcopy`, the final success line (`Published Trivy logs to ...`) goes to clipboard (stdout), while Trivy `INFO/WARN` logs still appear in terminal (stderr).

Optional overrides:

- `TRIVY_DB_REPOSITORY` (default: `registry.local.jazziro.com/ghcrio/aquasecurity/trivy-db:2`)
- `TRIVY_JAVA_DB_REPOSITORY` (default: `registry.local.jazziro.com/ghcrio/aquasecurity/trivy-java-db:1`)
- `OTLP_AUTH_HEADER`
- `SKIP_VEX_REPO_UPDATE=true|false`
- `PUBLISH_RETRIES` and `PUBLISH_BACKOFF_SECONDS`

Flag form is also supported:

```bash
./publish-trivy-otlp.sh \
  --image "nginx:1.27-alpine" \
  --db-repository "registry.local.jazziro.com/ghcrio/aquasecurity/trivy-db:2" \
  --java-db-repository "registry.local.jazziro.com/ghcrio/aquasecurity/trivy-java-db:1" \
  --otlp-logs-url "http://localhost:4318/v1/logs"
```

Show script help:

```bash
./publish-trivy-otlp.sh --help
```

## OTLP endpoint examples

- SigNoz: `OTLP_LOGS_URL=http://<signoz-host>:4318/v1/logs`
- Grafana Cloud: `OTLP_LOGS_URL=https://otlp-gateway-<region>.grafana.net/otlp/v1/logs`
- Grafana Cloud auth: `OTLP_AUTH_HEADER="Basic <base64(instance_id:api_key)>"`

## Dashboard

Import-ready SigNoz dashboard JSON:

- `zero-trust/trivy/signoz-trivy-vuln-dashboard.json`
