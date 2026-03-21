# Trivy VEX Local Repository

This directory serves a self-contained VEX repository for Trivy:

- Downloads the upstream VEX manifest at container startup
- Downloads the upstream VEX archive (`main.zip`) at container startup
- Rewrites manifest `locations[0].url` to your local server URL
- Serves both files locally to Trivy

The manifest is available from:

`/.well-known/vex-repository.json`

## Run a local HTTP server (quick)

```bash
npx -y http-server . -p 8080
```

## Run with Docker

Build:

```bash
docker build -t trivy-vex-repo .
```

Run:

```bash
docker run --rm -p 8080:8080 trivy-vex-repo
```

Optional: override upstream sources and public URL used in manifest:

```bash
docker run --rm -p 8080:8080 \
  -e PUBLIC_BASE_URL="http://localhost:8080" \
  -e VEX_REPOSITORY_URL="https://raw.githubusercontent.com/aquasecurity/vexhub/main/vex-repository.json" \
  -e VEX_ARCHIVE_URL="https://github.com/aquasecurity/vexhub/archive/refs/heads/main.zip" \
  trivy-vex-repo
```

If your host port differs from container port `8080`, set `PUBLIC_BASE_URL` to the externally reachable URL.

## Manifest endpoint

```text
http://localhost:8080/.well-known/vex-repository.json
```

The local archive URL that gets written into the manifest:

```text
http://localhost:8080/main.zip
```

## Test with Trivy image scan

```bash
export IMAGE="nginx:1.27-alpine"
trivy image \
  --scanners vuln \
  --vex repo \
  --vex-repo "http://localhost:8080/.well-known/vex-repository.json" \
  --skip-vex-repo-update \
  "$IMAGE"
```

## Export Trivy results to OpenTelemetry (SigNoz or Grafana)

Trivy does not export OTLP directly. The common pattern is:

1. Run Trivy in JSON mode
2. Convert findings to NDJSON (one vulnerability event per line)
3. Ship the file as OpenTelemetry logs with OTel Collector

### 1) Generate Trivy JSON report

```bash
export IMAGE="nginx:1.27-alpine"
trivy image \
  --scanners vuln \
  --vex repo \
  --vex-repo "http://localhost:8080/.well-known/vex-repository.json" \
  --skip-vex-repo-update \
  --format json \
  -o trivy-report.json \
  "$IMAGE"
```

### 2) Convert to NDJSON events

```bash
jq -c --arg image "$IMAGE" '
  .Results[]? as $r
  | $r.Vulnerabilities[]?
  | {
      timestamp: (now | todateiso8601),
      image: $image,
      target: $r.Target,
      class: $r.Class,
      type: $r.Type,
      vulnerability_id: .VulnerabilityID,
      severity: .Severity,
      package: .PkgName,
      installed_version: .InstalledVersion,
      fixed_version: .FixedVersion,
      title: .Title
    }' trivy-report.json > trivy-vulns.ndjson
```

### 3) Send to OTEL Collector

Create `otel-collector.yaml`:

```yaml
receivers:
  filelog:
    include: [ ./trivy-vulns.ndjson ]
    start_at: beginning
    operators:
      - type: json_parser

processors:
  resource:
    attributes:
      - key: service.name
        value: trivy-scan
        action: upsert

exporters:
  otlphttp/signoz:
    endpoint: http://localhost:4318

  otlphttp/grafana:
    endpoint: https://otlp-gateway-<region>.grafana.net/otlp
    headers:
      Authorization: Basic <base64(instance_id:api_key)>

service:
  pipelines:
    logs/signoz:
      receivers: [filelog]
      processors: [resource]
      exporters: [otlphttp/signoz]
    # Enable this pipeline when sending to Grafana Cloud
    logs/grafana:
      receivers: [filelog]
      processors: [resource]
      exporters: [otlphttp/grafana]
```

Run collector:

```bash
otelcol --config otel-collector.yaml
```

### Notes

- Model Trivy vulnerability findings as logs (not traces).
- For SigNoz, use your SigNoz OTLP endpoint (often `http://<signoz-host>:4318`).
- For Grafana Cloud, use your stack OTLP gateway and API key.

## Quick publish with Docker (scan + send OTLP + exit)

Use the helper script in this directory:

```bash
IMAGE="nginx:1.27-alpine" \
VEX_REPO_URL="http://localhost:8080/.well-known/vex-repository.json" \
OTLP_LOGS_URL="http://localhost:4318/v1/logs" \
./publish-trivy-otlp.sh
```

Or pass values as flags:

```bash
./publish-trivy-otlp.sh \
  --image "nginx:1.27-alpine" \
  --vex-repo-url "http://localhost:8080/.well-known/vex-repository.json" \
  --otlp-logs-url "http://localhost:4318/v1/logs"
```

`--flag value` and `--flag=value` are both supported.

Required variables:

- `IMAGE`
- `VEX_REPO_URL`
- `OTLP_LOGS_URL`

Optional variables:

- `OTLP_AUTH_HEADER` (default: empty)
- `VERIFY_VEX_REPO` (default: `true`)
- `SKIP_VEX_REPO_UPDATE` (default: `false`)
- `PUBLISH_RETRIES` (default: `3`)
- `PUBLISH_BACKOFF_SECONDS` (default: `2`)

Flag equivalents:

- `--image`
- `--vex-repo-url`
- `--otlp-logs-url`
- `--otlp-auth-header`
- `--verify-vex-repo true|false`
- `--publish-retries <int>`
- `--publish-backoff <seconds>`

Show help:

```bash
./publish-trivy-otlp.sh --help
```

### Run the script in Docker

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  -e IMAGE="nginx:1.27-alpine" \
  -e VEX_REPO_URL="http://host.docker.internal:8080/.well-known/vex-repository.json" \
  -e OTLP_LOGS_URL="http://host.docker.internal:4318/v1/logs" \
  -e OTLP_AUTH_HEADER="" \
  aquasec/trivy:latest sh -ec 'apk add --no-cache jq curl >/dev/null && ./publish-trivy-otlp.sh'
```

Script behavior:

- `IMAGE` is required
- `VEX_REPO_URL` is required (manifest URL or repo base URL)
- `OTLP_LOGS_URL` is required
- `OTLP_AUTH_HEADER=` (empty)
- validates URL format and checks VEX manifest reachability before scanning
- retries OTLP publish with exponential backoff (default: 3 retries)

Published log fields include the table-style vulnerability details:

- `library` (`package`)
- `vulnerability_id`
- `severity`
- `status`
- `installed_version`
- `fixed_version`
- `title`
- `primary_url`

Semantic-convention style fields are also included for easier querying:

- `event.name=security.vulnerability`
- `event.domain=security`
- `event.type=vulnerability`
- `container.image.name`
- `package.name`, `package.version`
- `vulnerability.id`, `vulnerability.severity`, `vulnerability.status`, `vulnerability.title`, `vulnerability.reference`

The script also sets OTLP `severityNumber` from Trivy severity (`CRITICAL/HIGH/MEDIUM/LOW/UNKNOWN`).

Additionally, each run always emits a scan summary event:

- `event.name=security.scan.summary`
- `security.scan.result=clean|vulnerable`
- `scan.vulnerability.count=<number>`

This makes zero-vulnerability scans visible in dashboards.

### Endpoint examples

- SigNoz: `OTLP_LOGS_URL=http://<signoz-host>:4318/v1/logs`
- Grafana Cloud: `OTLP_LOGS_URL=https://otlp-gateway-<region>.grafana.net/otlp/v1/logs`
- Grafana Cloud auth: `OTLP_AUTH_HEADER="Basic <base64(instance_id:api_key)>"`

## Visualize in SigNoz or Grafana

- SigNoz: open Logs, filter `service.name="trivy-scan"`, then create dashboard widgets for count by `severity`, top `vulnerability_id`, and top `package`.
- Grafana: open Explore, query logs for `service.name="trivy-scan"`, then build panels for vulnerabilities over time and severity breakdown.

## SigNoz dashboard JSON (import-ready)

A ready-to-import SigNoz dashboard is available at:

- `zero-trust/trivy/signoz-trivy-vuln-dashboard.json`

Import in SigNoz:

1. Open **Dashboards**.
2. Click **New Dashboard** (or import option in your version).
3. Upload `signoz-trivy-vuln-dashboard.json`.
4. Save layout.

This dashboard includes:

- total/critical/high counters
- vulnerabilities over time by severity
- detailed vulnerability table with `Library`, `Vulnerability`, `Severity`, `Status`, `Installed Version`, `Fixed Version`, `Title`, and `URL`
- top images and status breakdown
- latest scan result by image (includes clean scans)
