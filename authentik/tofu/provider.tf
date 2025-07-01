terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      version = "~> 2025.2"
    }
  }
}

provider "authentik" {
  # Configuration options
  url   = var.authentik_url
  token = var.authentik_token
  # Optionally set insecure to ignore TLS Certificates
  # insecure = true
  # Optionally add extra headers
  # headers {
  #   X-my-header = "foo"
  # }
}