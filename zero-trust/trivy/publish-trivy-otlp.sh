#!/usr/bin/env sh
set -eu

IMAGE="${IMAGE:-}"
VEX_REPO_URL="${VEX_REPO_URL:-https://raw.githubusercontent.com/aquasecurity/vexhub/main/vex-repository.json}"
OTLP_LOGS_URL="${OTLP_LOGS_URL:-}"
OTLP_AUTH_HEADER="${OTLP_AUTH_HEADER:-}"
VERIFY_VEX_REPO="${VERIFY_VEX_REPO:-true}"
SKIP_VEX_REPO_UPDATE="${SKIP_VEX_REPO_UPDATE:-false}"
TRIVY_DB_REPOSITORY="${TRIVY_DB_REPOSITORY:-registry.local.jazziro.com/ghcrio/aquasecurity/trivy-db:2}"
TRIVY_JAVA_DB_REPOSITORY="${TRIVY_JAVA_DB_REPOSITORY:-registry.local.jazziro.com/ghcrio/aquasecurity/trivy-java-db:1}"
PUBLISH_RETRIES="${PUBLISH_RETRIES:-3}"
PUBLISH_BACKOFF_SECONDS="${PUBLISH_BACKOFF_SECONDS:-2}"

usage() {
  cat <<'EOF'
Usage:
  IMAGE=<required-image> OTLP_LOGS_URL=<required-endpoint> ./publish-trivy-otlp.sh
  ./publish-trivy-otlp.sh --image <image> --vex-repo-url <url> --otlp-logs-url <url> [options]

Optional environment variables:
  VEX_REPO_URL=<url>               VEX manifest URL or base URL (default: upstream VEX Hub manifest)
  VERIFY_VEX_REPO=true|false       Verify VEX manifest URL before scan (default: true)
  TRIVY_DB_REPOSITORY=<oci-ref>    Trivy DB OCI reference (default: jazziro proxy)
  TRIVY_JAVA_DB_REPOSITORY=<ref>   Trivy Java DB OCI reference (default: jazziro proxy)

Flags:
  --image <image>               Container image to scan (required if IMAGE is unset)
  --vex-repo-url <url>          VEX repo base URL or manifest URL
  --db-repository <oci-ref>     Trivy DB OCI reference
  --java-db-repository <ref>    Trivy Java DB OCI reference
  --otlp-logs-url <url>         OTLP logs endpoint (required if OTLP_LOGS_URL is unset)
  --otlp-auth-header <value>    Optional Authorization header value
  --verify-vex-repo <bool>      true|false (default: true)
  --skip-vex-repo-update <bool> true|false (default: false)
  --publish-retries <int>       Number of publish retries (default: 3)
  --publish-backoff <seconds>   Base backoff seconds (default: 2)
  -h, --help                    Show this help

Examples:
  IMAGE=nginx:1.27-alpine OTLP_LOGS_URL=http://localhost:4318/v1/logs ./publish-trivy-otlp.sh
  OTLP_LOGS_URL=https://otlp-gateway-us.grafana.net/otlp/v1/logs \
  OTLP_AUTH_HEADER="Basic <base64(instance_id:api_key)>" \
  ./publish-trivy-otlp.sh
  ./publish-trivy-otlp.sh \
    --image nginx:1.27-alpine \
    --vex-repo-url https://raw.githubusercontent.com/aquasecurity/vexhub/main/vex-repository.json \
    --db-repository registry.local.jazziro.com/ghcrio/aquasecurity/trivy-db:2 \
    --java-db-repository registry.local.jazziro.com/ghcrio/aquasecurity/trivy-java-db:1 \
    --otlp-logs-url http://localhost:4318/v1/logs
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --image=*)
        IMAGE="${1#*=}"
        shift
        ;;
      --image)
        [ "$#" -ge 2 ] || { echo "Missing value for --image" >&2; exit 1; }
        IMAGE="$2"
        shift 2
        ;;
      --vex-repo-url=*)
        VEX_REPO_URL="${1#*=}"
        shift
        ;;
      --vex-repo-url)
        [ "$#" -ge 2 ] || { echo "Missing value for --vex-repo-url" >&2; exit 1; }
        VEX_REPO_URL="$2"
        shift 2
        ;;
      --otlp-logs-url=*)
        OTLP_LOGS_URL="${1#*=}"
        shift
        ;;
      --db-repository=*)
        TRIVY_DB_REPOSITORY="${1#*=}"
        shift
        ;;
      --db-repository)
        [ "$#" -ge 2 ] || { echo "Missing value for --db-repository" >&2; exit 1; }
        TRIVY_DB_REPOSITORY="$2"
        shift 2
        ;;
      --java-db-repository=*)
        TRIVY_JAVA_DB_REPOSITORY="${1#*=}"
        shift
        ;;
      --java-db-repository)
        [ "$#" -ge 2 ] || { echo "Missing value for --java-db-repository" >&2; exit 1; }
        TRIVY_JAVA_DB_REPOSITORY="$2"
        shift 2
        ;;
      --otlp-logs-url)
        [ "$#" -ge 2 ] || { echo "Missing value for --otlp-logs-url" >&2; exit 1; }
        OTLP_LOGS_URL="$2"
        shift 2
        ;;
      --otlp-auth-header=*)
        OTLP_AUTH_HEADER="${1#*=}"
        shift
        ;;
      --otlp-auth-header)
        [ "$#" -ge 2 ] || { echo "Missing value for --otlp-auth-header" >&2; exit 1; }
        OTLP_AUTH_HEADER="$2"
        shift 2
        ;;
      --verify-vex-repo=*)
        VERIFY_VEX_REPO="${1#*=}"
        shift
        ;;
      --verify-vex-repo)
        [ "$#" -ge 2 ] || { echo "Missing value for --verify-vex-repo" >&2; exit 1; }
        VERIFY_VEX_REPO="$2"
        shift 2
        ;;
      --skip-vex-repo-update=*)
        SKIP_VEX_REPO_UPDATE="${1#*=}"
        shift
        ;;
      --skip-vex-repo-update)
        [ "$#" -ge 2 ] || { echo "Missing value for --skip-vex-repo-update" >&2; exit 1; }
        SKIP_VEX_REPO_UPDATE="$2"
        shift 2
        ;;
      --publish-retries=*)
        PUBLISH_RETRIES="${1#*=}"
        shift
        ;;
      --publish-retries)
        [ "$#" -ge 2 ] || { echo "Missing value for --publish-retries" >&2; exit 1; }
        PUBLISH_RETRIES="$2"
        shift 2
        ;;
      --publish-backoff=*)
        PUBLISH_BACKOFF_SECONDS="${1#*=}"
        shift
        ;;
      --publish-backoff)
        [ "$#" -ge 2 ] || { echo "Missing value for --publish-backoff" >&2; exit 1; }
        PUBLISH_BACKOFF_SECONDS="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

parse_args "$@"

validate_url() {
  value="$1"
  name="$2"
  case "$value" in
    http://*|https://*) ;;
    *)
      echo "${name} must start with http:// or https://, got: ${value}" >&2
      exit 1
      ;;
  esac
}

if ! command -v trivy >/dev/null 2>&1; then
  echo "Missing dependency: trivy" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing dependency: jq" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing dependency: curl" >&2
  exit 1
fi

if [ -z "${IMAGE}" ]; then
  echo "IMAGE is required" >&2
  usage
  exit 1
fi

if [ -z "${OTLP_LOGS_URL}" ]; then
  echo "OTLP_LOGS_URL is required" >&2
  usage
  exit 1
fi

case "${VERIFY_VEX_REPO}" in
  true|false) ;;
  *)
    echo "VERIFY_VEX_REPO must be true or false, got: ${VERIFY_VEX_REPO}" >&2
    exit 1
    ;;
esac

case "${SKIP_VEX_REPO_UPDATE}" in
  true|false) ;;
  *)
    echo "SKIP_VEX_REPO_UPDATE must be true or false, got: ${SKIP_VEX_REPO_UPDATE}" >&2
    exit 1
    ;;
esac

case "${PUBLISH_RETRIES}" in
  ''|*[!0-9]*)
    echo "PUBLISH_RETRIES must be a non-negative integer, got: ${PUBLISH_RETRIES}" >&2
    exit 1
    ;;
esac

case "${PUBLISH_BACKOFF_SECONDS}" in
  ''|*[!0-9]*)
    echo "PUBLISH_BACKOFF_SECONDS must be a non-negative integer, got: ${PUBLISH_BACKOFF_SECONDS}" >&2
    exit 1
    ;;
esac

case "${VEX_REPO_URL}" in
  */.well-known/vex-repository.json)
    VEX_REPO_BASE_URL="${VEX_REPO_URL%/.well-known/vex-repository.json}"
    VEX_MANIFEST_URL="${VEX_REPO_URL}"
    ;;
  *)
    VEX_REPO_BASE_URL="${VEX_REPO_URL%/}"
    VEX_MANIFEST_URL="${VEX_REPO_BASE_URL}/.well-known/vex-repository.json"
    ;;
esac

validate_url "${VEX_REPO_URL}" "VEX_REPO_URL"
validate_url "${OTLP_LOGS_URL}" "OTLP_LOGS_URL"

if [ -z "${TRIVY_DB_REPOSITORY}" ]; then
  echo "TRIVY_DB_REPOSITORY must not be empty" >&2
  exit 1
fi

if [ -z "${TRIVY_JAVA_DB_REPOSITORY}" ]; then
  echo "TRIVY_JAVA_DB_REPOSITORY must not be empty" >&2
  exit 1
fi

case "${OTLP_LOGS_URL}" in
  */v1/logs) ;;
  *)
    echo "OTLP_LOGS_URL should usually end with /v1/logs, got: ${OTLP_LOGS_URL}" >&2
    ;;
esac

if [ "${VERIFY_VEX_REPO}" = "true" ]; then
  echo "Validating VEX manifest URL: ${VEX_MANIFEST_URL}"
  if ! curl -fsS "${VEX_MANIFEST_URL}" >/dev/null; then
    echo "Failed to reach VEX manifest URL: ${VEX_MANIFEST_URL}" >&2
    exit 1
  fi
fi

TMP_JSON="$(mktemp)"
TMP_OTLP="$(mktemp)"
TMP_XDG_DATA_HOME="$(mktemp -d)"
trap 'rm -f "$TMP_JSON" "$TMP_OTLP"; rm -rf "$TMP_XDG_DATA_HOME"' EXIT

mkdir -p "${TMP_XDG_DATA_HOME}/.trivy/vex"
cat > "${TMP_XDG_DATA_HOME}/.trivy/vex/repository.yaml" <<EOF
repositories:
  - name: local
    url: ${VEX_REPO_BASE_URL}
    enabled: true
    username: ""
    password: ""
    token: ""
EOF

echo "Scanning image: ${IMAGE}"
echo "Using Trivy DB: ${TRIVY_DB_REPOSITORY}"
echo "Using Trivy Java DB: ${TRIVY_JAVA_DB_REPOSITORY}"
TRIVY_CMD="trivy image --scanners vuln --vex repo --db-repository ${TRIVY_DB_REPOSITORY} --java-db-repository ${TRIVY_JAVA_DB_REPOSITORY} --format json -o ${TMP_JSON} ${IMAGE}"
if [ "${SKIP_VEX_REPO_UPDATE}" = "true" ]; then
  TRIVY_CMD="${TRIVY_CMD} --skip-vex-repo-update"
fi

XDG_DATA_HOME="${TMP_XDG_DATA_HOME}" sh -c "${TRIVY_CMD}"

VULN_COUNT="$(jq '[.Results[]? | .Vulnerabilities[]?] | length' "${TMP_JSON}")"
echo "Vulnerabilities found: ${VULN_COUNT}"

TS="$(date +%s%N)"

jq -c --arg image "${IMAGE}" --arg ts "${TS}" --arg vuln_count "${VULN_COUNT}" '
  [ .Results[]? as $r | $r.Vulnerabilities[]? | {
      sev: (.Severity // "UNSPECIFIED"),
      sev_num: (
        if (.Severity // "") == "CRITICAL" then 21
        elif (.Severity // "") == "HIGH" then 17
        elif (.Severity // "") == "MEDIUM" then 13
        elif (.Severity // "") == "LOW" then 9
        elif (.Severity // "") == "UNKNOWN" then 5
        else 1
        end
      ),
      status: (.Status // "unknown"),
      cve: (.VulnerabilityID // ""),
      pkg: (.PkgName // ""),
      installed: (.InstalledVersion // ""),
      fixed: (.FixedVersion // ""),
      title: (.Title // ""),
      primary_url: (.PrimaryURL // ""),
      target: ($r.Target // "")
    }
  ] as $v
  | {
      counts: {
        total: ($v | length),
        low: ($v | map(select(.sev == "LOW")) | length),
        medium: ($v | map(select(.sev == "MEDIUM")) | length),
        high: ($v | map(select(.sev == "HIGH")) | length),
        critical: ($v | map(select(.sev == "CRITICAL")) | length),
        unknown: ($v | map(select(.sev == "UNKNOWN" or .sev == "UNSPECIFIED")) | length)
      },
      timeUnixNano: $ts,
      severityNumber: (if ($vuln_count | tonumber) > 0 then 13 else 9 end),
      severityText: (if ($vuln_count | tonumber) > 0 then "WARN" else "INFO" end),
      body: {stringValue: ("trivy scan result image=" + $image + " vulnerabilities=" + $vuln_count)},
      attributes: [
        {key:"event.name", value:{stringValue:"security.scan.summary"}},
        {key:"event.domain", value:{stringValue:"security"}},
        {key:"event.type", value:{stringValue:"scan"}},
        {key:"container.image.name", value:{stringValue:$image}},
        {key:"image", value:{stringValue:$image}},
        {key:"scan.vulnerability.count", value:{stringValue:$vuln_count}},
        {key:"scan.vulnerability.count.total", value:{stringValue:(.counts.total|tostring)}},
        {key:"scan.vulnerability.count.low", value:{stringValue:(.counts.low|tostring)}},
        {key:"scan.vulnerability.count.medium", value:{stringValue:(.counts.medium|tostring)}},
        {key:"scan.vulnerability.count.high", value:{stringValue:(.counts.high|tostring)}},
        {key:"scan.vulnerability.count.critical", value:{stringValue:(.counts.critical|tostring)}},
        {key:"scan.vulnerability.count.unknown", value:{stringValue:(.counts.unknown|tostring)}},
        {key:"security.scan.result", value:{stringValue:(if ($vuln_count | tonumber) > 0 then "vulnerable" else "clean" end)}}
      ]
    } as $summary
  | {
      resourceLogs: [{
        resource: { attributes: [{key:"service.name", value:{stringValue:"trivy-scan"}}] },
        scopeLogs: [{
          scope: {name:"trivy-cli"},
          logRecords: ([$summary] + ($v | map({
            timeUnixNano: $ts,
            severityNumber: .sev_num,
            severityText: .sev,
            body: {stringValue: (.pkg + " | " + .cve + " | " + .sev + " | " + .status + " | " + .installed + " | " + .fixed + " | " + .title + (if .primary_url != "" then " | " + .primary_url else "" end))},
            attributes: [
              {key:"event.name", value:{stringValue:"security.vulnerability"}},
              {key:"event.domain", value:{stringValue:"security"}},
              {key:"event.type", value:{stringValue:"vulnerability"}},
              {key:"container.image.name", value:{stringValue:$image}},
              {key:"package.name", value:{stringValue:.pkg}},
              {key:"package.version", value:{stringValue:.installed}},
              {key:"vulnerability.id", value:{stringValue:.cve}},
              {key:"vulnerability.severity", value:{stringValue:.sev}},
              {key:"vulnerability.status", value:{stringValue:.status}},
              {key:"vulnerability.title", value:{stringValue:.title}},
              {key:"vulnerability.reference", value:{stringValue:.primary_url}},
              {key:"image", value:{stringValue:$image}},
              {key:"target", value:{stringValue:.target}},
              {key:"library", value:{stringValue:.pkg}},
              {key:"vulnerability_id", value:{stringValue:.cve}},
              {key:"severity", value:{stringValue:.sev}},
              {key:"status", value:{stringValue:.status}},
              {key:"package", value:{stringValue:.pkg}},
              {key:"installed_version", value:{stringValue:.installed}},
              {key:"fixed_version", value:{stringValue:.fixed}},
              {key:"title", value:{stringValue:.title}},
              {key:"primary_url", value:{stringValue:.primary_url}}
            ]
          })))
        }]
      }]
    }
' "${TMP_JSON}" > "${TMP_OTLP}"

attempt=0
max_attempts=$((PUBLISH_RETRIES + 1))
while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))

  if [ -n "${OTLP_AUTH_HEADER}" ]; then
    if curl -fsS -X POST "${OTLP_LOGS_URL}" \
      -H "Content-Type: application/json" \
      -H "Authorization: ${OTLP_AUTH_HEADER}" \
      --data @"${TMP_OTLP}"; then
      break
    fi
  else
    if curl -fsS -X POST "${OTLP_LOGS_URL}" \
      -H "Content-Type: application/json" \
      --data @"${TMP_OTLP}"; then
      break
    fi
  fi

  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "Failed to publish logs after ${max_attempts} attempt(s)" >&2
    exit 1
  fi

  sleep_seconds=$((PUBLISH_BACKOFF_SECONDS * (2 ** (attempt - 1))))
  echo "Publish attempt ${attempt}/${max_attempts} failed; retrying in ${sleep_seconds}s..." >&2
  sleep "$sleep_seconds"
done

echo "Published Trivy logs to ${OTLP_LOGS_URL}"
