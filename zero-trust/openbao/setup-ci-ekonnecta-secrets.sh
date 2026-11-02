#!/usr/bin/env bash
#
# Create (or update) the OpenBao KV secrets consumed by the ekonnecta GitLab CI
# pipeline, under the path:
#
#   secret/ci/ekonnecta/{registry,database,argocd,gitlab}
#
# Values default to placeholders (REPLACE_ME). Override any value by exporting
# the matching environment variable before running, e.g.:
#
#   export CONTAINER_REGISTRY_PASSWORD='...'
#   export PROD_DATABASE_URL='postgres://...'
#   export ARGOCD_PAT='...'
#   export GITLAB_PAT='...'
#
# Requires an admin token (root or platform-admin) that can write under
# secret/. The token is read from BAO_TOKEN or prompted for, and is never
# printed or written to disk.
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
PROD_DATABASE_URL="${PROD_DATABASE_URL:-postgres://REPLACE_ME:REPLACE_ME@REPLACE_ME:5432/ekonnecta}"
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd.iysynergy.com}"
ARGOCD_PAT="${ARGOCD_PAT:-REPLACE_ME}"
GITLAB_PAT="${GITLAB_PAT:-REPLACE_ME}"

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
    PROD_DATABASE_URL ARGOCD_SERVER ARGOCD_PAT GITLAB_PAT
}
trap cleanup EXIT

# Verify the token works and can write under secret/.
if ! bao token lookup >/dev/null 2>&1; then
  echo "error: token is not valid for $BAO_ADDR" >&2
  exit 1
fi

echo "Writing secret/ci/ekonnecta/registry"
bao kv put secret/ci/ekonnecta/registry \
  CONTAINER_REGISTRY_URL="$CONTAINER_REGISTRY_URL" \
  CONTAINER_REGISTRY_USERNAME="$CONTAINER_REGISTRY_USERNAME" \
  CONTAINER_REGISTRY_PASSWORD="$CONTAINER_REGISTRY_PASSWORD" >/dev/null

echo "Writing secret/ci/ekonnecta/database"
bao kv put secret/ci/ekonnecta/database \
  PROD_DATABASE_URL="$PROD_DATABASE_URL" >/dev/null

echo "Writing secret/ci/ekonnecta/argocd"
bao kv put secret/ci/ekonnecta/argocd \
  ARGOCD_SERVER="$ARGOCD_SERVER" \
  ARGOCD_PAT="$ARGOCD_PAT" >/dev/null

echo "Writing secret/ci/ekonnecta/gitlab"
bao kv put secret/ci/ekonnecta/gitlab \
  GITLAB_PAT="$GITLAB_PAT" >/dev/null

echo
echo "Created/updated ekonnecta CI secrets under secret/ci/ekonnecta/"
bao kv list secret/ci/ekonnecta
echo
echo "Replace any REPLACE_ME values via the OpenBao UI or 'bao kv patch', e.g.:"
echo "  bao kv patch secret/ci/ekonnecta/gitlab GITLAB_PAT='glpat-...'"
