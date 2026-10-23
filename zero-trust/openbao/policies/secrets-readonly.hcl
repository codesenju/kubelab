# secrets-readonly
#
# Read-only access to every path.
# Grants read and list only: no create, update, delete, or sudo.
#
# Note: read on "*" includes readable sys/ endpoints and all secret engines.
# It does not grant sudo-only operations such as sys/raw or seal/unseal.

path "*" {
  capabilities = ["read", "list"]
}
