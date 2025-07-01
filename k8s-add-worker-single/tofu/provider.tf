terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.2"
    }
  }
}

provider "proxmox" {
  insecure = true
}