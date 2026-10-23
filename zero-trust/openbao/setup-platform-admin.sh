#!/usr/bin/env bash
#
# Create (or rotate) the non-root platform-admin OpenBao token.
#
# Requires a one-time root/admin token with permission to write policies and
# create tokens. The root token is read from BAO_TOKEN or prompted for, and is
# never printed or written to disk.
#
# Usage:
#   export BAO_ADDR="https://openbao.local.example.com"
#   read -rsp "Root token: " BAO_TOKEN; echo; export BAO_TOKEN
#   bash zero-trust/openbao/setup-platform-admin.sh
#   unset BAO_TOKEN
#
# Output:
#   ~/.config/openbao/platform-admin.token  (mode 600)
#
# Re-running the script revokes the previously generated token before creating
# a replacement.

set -euo pipefail

BAO_ADDR="${BAO_ADDR:-https://openbao.local.example.com}"
export BAO_ADDR

POLICY_NAME="${POLICY_NAME:-platform-admin}"
POLICY_FILE="${POLICY_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policies/platform-admin.hcl}"
TOKEN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openbao"
TOKEN_FILE="${TOKEN_FILE:-$TOKEN_DIR/platform-admin.token}"

if ! command -v bao >/dev/null 2>&1; then
  echo "error: bao CLI not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "error: policy file not found: $POLICY_FILE" >&2
  exit 1
fi

if [[ -z "${BAO_TOKEN:-}" ]]; then
  read -rsp "Root token: " BAO_TOKEN
  echo >&2
  export BAO_TOKEN
fi

OLD_TOKEN=""
NEW_TOKEN=""

cleanup() {
  unset BAO_TOKEN OLD_TOKEN NEW_TOKEN
}
trap cleanup EXIT

# Verify the supplied token works and can administer policies.
if ! bao token lookup >/dev/null 2>&1; then
  echo "error: token is not valid for $BAO_ADDR" >&2
  exit 1
fi

if ! bao policy list >/dev/null 2>&1; then
  echo "error: token cannot manage policies; use the root token" >&2
  exit 1
fi

# Revoke the previous generated token, if any, so rotation does not leave
# live credentials behind.
if [[ -s "$TOKEN_FILE" ]]; then
  OLD_TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
  if [[ -n "$OLD_TOKEN" ]]; then
    bao token revoke "$OLD_TOKEN" >/dev/null 2>&1 || true
  fi
  rm -f "$TOKEN_FILE"
fi

echo "Writing policy: $POLICY_NAME"
bao policy write "$POLICY_NAME" "$POLICY_FILE" >/dev/null

echo "Creating token: $POLICY_NAME"
CREATE_JSON="$(bao token create \
  -policy="$POLICY_NAME" \
  -display-name="$POLICY_NAME" \
  -orphan \
  -period=768h \
  -ttl=768h \
  -format=json)"

NEW_TOKEN="$(printf '%s' "$CREATE_JSON" | jq -r '.auth.client_token // empty')"
unset CREATE_JSON

if [[ -z "$NEW_TOKEN" ]]; then
  echo "error: token creation did not return a token" >&2
  exit 1
fi

mkdir -p "$TOKEN_DIR"
(umask 077; printf '%s' "$NEW_TOKEN" > "$TOKEN_FILE")
chmod 600 "$TOKEN_FILE"

# Prove the new token works for the requested administrative duties.
if ! BAO_TOKEN="$NEW_TOKEN" bao token lookup >/dev/null 2>&1; then
  echo "error: new token failed lookup" >&2
  exit 1
fi
if ! BAO_TOKEN="$NEW_TOKEN" bao policy list >/dev/null 2>&1; then
  echo "error: new token cannot list policies" >&2
  exit 1
fi
if ! BAO_TOKEN="$NEW_TOKEN" bao auth list >/dev/null 2>&1; then
  echo "error: new token cannot list auth methods" >&2
  exit 1
fi

echo
echo "Created non-root admin token."
echo "  policy:     $POLICY_NAME"
echo "  token file: $TOKEN_FILE (mode 600)"
echo
echo "Load it with:"
echo "  export BAO_TOKEN=\"\$(cat $TOKEN_FILE)\""
echo
echo "The root token was not stored. Unset it in your shell:"
echo "  unset BAO_TOKEN"
