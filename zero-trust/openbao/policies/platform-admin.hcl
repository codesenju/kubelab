# platform-admin
#
# Root-equivalent administration without using the root token.
# Grants management of policies, auth methods (including OIDC), secrets
# engines, identities, tokens, leases, audit devices, and all secret data.
#
# This policy is intentionally broad. The resulting token is NOT the root
# token: it is named, periodic, auditable, and can be revoked independently.

path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
