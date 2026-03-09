terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.0"
    }
  }
}

provider "proxmox" {
  insecure = true
}

terraform {
  backend "s3" {
    bucket = "kubelab-tofu"
    key    = "k8s-control-plane.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "https://drives3.iysynergy.com"
    }

    use_path_style = true
    use_lockfile   = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
