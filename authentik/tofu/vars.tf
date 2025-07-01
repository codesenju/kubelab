variable "authentik_url" {
    type = string
    description = "Authentik URL"
}

variable "authentik_token" {
    type = string
    description = "Authentik Token"
}

variable "argocd_allowed_redirect_uris" {
    type = string
    description = "ArgoCD Allowed Redirect URIs"
}

variable "argocd_client_secret" {
    type = string
    description = "ArgoCD Client Secret"
}