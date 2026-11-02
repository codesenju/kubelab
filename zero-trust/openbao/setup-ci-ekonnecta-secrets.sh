#!/usr/bin/env bash
#
# Create (or update) the OpenBao KV secret consumed by CI pipelines, stored as
# a single secret at:
#
#   secret/ci
#
# Shared CI keys are unprefixed; app-specific values carry an app prefix
# (EKONNECTA_) so multiple apps can share the same secret/ci path:
#
#   CONTAINER_REGISTRY_URL
#   CONTAINER_REGISTRY_USERNAME
#   CONTAINER_REGISTRY_PASSWORD
#   ARGOCD_SERVER
#   ARGOCD_PAT
#   EKONNECTA_PROD_DATABASE_URL
#   EKONNECTA_GITLAB_PAT
#
# Values default to placeholders (REPLACE_ME). Override any value by exporting
# the matching environment variable before running, e.g.:
#
#   export CONTAINER_REGISTRY_PASSWORD='...'
#   export EKONNECTA_PROD_DATABASE_URL='postgres://...'
#   export ARGOCD_PAT='...'
#   export EKONNECTA_GITLAB_PAT='...'
#
# Requires an admin token (root or platform-admin) that can write under
# secret/. The token is read from BAO_TOKEN or prompted for, and is never
# printed or written to disk.
#
# NOTE: `bao kv put secret/ci ...` replaces the whole secret. To change a
# single field without touching the rest, use `bao kv patch secret/ci KEY=...`.
#
# Usage:
#   export BAO_ADDR="https://openbao.local.jazziro.com"
#   export BAO_TOKEN="$(cat ~/.config/openbao/platform-admin.token)"
#   bash zero-trust/openbao/setup-ci-ekonnecta-secrets.sh
#   unset BAO_TOKEN
#
# The GitLab CI pipeline reads these with a secrets-readonly token. See the
# "CI: ekonnecta pipeline" section in README.md.

set -euo pipefail

BAO_ADDR="${BAO_ADDR:-https://openbao.local.jazziro.com}"
export BAO_ADDR

# Defaults are safe placeholders; export the vars to supply real values.
CONTAINER_REGISTRY_URL="${CONTAINER_REGISTRY_URL:-registry.local.jazziro.com}"
CONTAINER_REGISTRY_USERNAME="${CONTAINER_REGISTRY_USERNAME:-REPLACE_ME}"
CONTAINER_REGISTRY_PASSWORD="${CONTAINER_REGISTRY_PASSWORD:-REPLACE_ME}"
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd.iysynergy.com}"
ARGOCD_PAT="${ARGOCD_PAT:-REPLACE_ME}"
EKONNECTA_PROD_DATABASE_URL="${EKONNECTA_PROD_DATABASE_URL:-postgres://REPLACE_ME:REPLACE_ME@REPLACE_ME:5432/ekonnecta}"
EKONNECTA_GITLAB_PAT="${EKONNECTA_GITLAB_PAT:-REPLACE_ME}"

if ! command -v bao >/dev/null 2>&1; then
  echo "error: bao CLI not found in PATH" >&2
  exit 1
fi

if [[ -z "${BAO_TOKEN:-}" ]]; then
  read -rsp "Admin token: " BAO_TOKEN
  echo >&2
  export BAO_TOKEN
fi

cleanup() {
  unset BAO_TOKEN \
    CONTAINER_REGISTRY_URL CONTAINER_REGISTRY_USERNAME CONTAINER_REGISTRY_PASSWORD \
    ARGOCD_SERVER ARGOCD_PAT EKONNECTA_PROD_DATABASE_URL EKONNECTA_GITLAB_PAT
}
trap cleanup EXIT

# Verify the token works and can write under secret/.
if ! bao token lookup >/dev/null 2>&1; then
  echo "error: token is not valid for $BAO_ADDR" >&2
  exit 1
fi

echo "Writing secret/ci"
bao kv put secret/ci \
  CONTAINER_REGISTRY_URL="$CONTAINER_REGISTRY_URL" \
  CONTAINER_REGISTRY_USERNAME="$CONTAINER_REGISTRY_USERNAME" \
  CONTAINER_REGISTRY_PASSWORD="$CONTAINER_REGISTRY_PASSWORD" \
  ARGOCD_SERVER="$ARGOCD_SERVER" \
  ARGOCD_PAT="$ARGOCD_PAT" \
  EKONNECTA_PROD_DATABASE_URL="$EKONNECTA_PROD_DATABASE_URL" \
  EKONNECTA_GITLAB_PAT="$EKONNECTA_GITLAB_PAT" >/dev/null

echo
echo "Created/updated CI secret at secret/ci with keys:"
bao kv get -format=json secret/ci | python3 -c "import sys,json; [print('  '+k) for k in sorted(json.load(sys.stdin)['data']['data'].keys())]"
echo
echo "Replace any REPLACE_ME values via the OpenBao UI or 'bao kv patch', e.g.:"
echo "  bao kv patch secret/ci EKONNECTA_GITLAB_PAT='glpat-...'"
