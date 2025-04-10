data "authentik_flow" "default-provider-authorization-implicit-consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default-provider-invalidation" {
  slug = "default-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "scope-email" {
  name = "authentik default OAuth Mapping: OpenID 'email'"
}

data "authentik_property_mapping_provider_scope" "scope-profile" {
  name = "authentik default OAuth Mapping: OpenID 'profile'"
}

data "authentik_property_mapping_provider_scope" "scope-openid" {
  name = "authentik default OAuth Mapping: OpenID 'openid'"
}

data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "argocd" {
  name          = "ArgoCD"
  #  Required. You can use the output of:
  #     $ openssl rand -hex 16
  client_id     = "argocd"

  # Optional: will be generated if not provided
  #     $ openssl rand base64 32
  client_secret = var.argocd_client_secret

  authorization_flow = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation.id

  signing_key = data.authentik_certificate_key_pair.generated.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = var.argocd_allowed_redirect_uris,
    },
    # {
    #   matching_mode = "strict",
    #   url           = "http://localhost:8085/auth/callback",
    # }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.scope-email.id,
    data.authentik_property_mapping_provider_scope.scope-profile.id,
    data.authentik_property_mapping_provider_scope.scope-openid.id,
  ]
}

resource "authentik_application" "argocd" {
  name              = "ArgoCD"
  slug              = "argocd"
  protocol_provider = authentik_provider_oauth2.argocd.id
}

resource "authentik_group" "argocd_admins" {
  name    = "ArgoCD Admins"
}

resource "authentik_group" "argocd_viewers" {
  name    = "ArgoCD Viewers"
}