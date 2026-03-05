# Plugin: bpg/proxmox
provider "proxmox" {
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_ENDPOINT= environment variable
  # endpoint = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_USERNAME environment variable
  # username = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_PASSWORD environment variable
  # password = ""
  insecure = true
}

resource "proxmox_virtual_environment_role" "csi" {
  role_id = "CSI"

  privileges = [
    "VM.Audit",
    "VM.Allocate",
    "VM.Clone",
    "VM.Config.CPU",
    "VM.Config.Disk",
    "VM.Config.HWType",
    "VM.Config.Memory",
    "VM.Config.Options",
    "VM.Migrate",
    "VM.PowerMgmt",
    "Datastore.Allocate",
    "Datastore.AllocateSpace",
    "Datastore.Audit"
  ]
}

resource "proxmox_virtual_environment_user" "kubernetes" {
  comment = "Kubernetes"
  user_id = "kubernetes-csi@pve"
}

resource "proxmox_virtual_environment_acl" "user" {
  user_id = proxmox_virtual_environment_user.kubernetes.user_id
  role_id = proxmox_virtual_environment_role.csi.role_id

  path      = "/"
  propagate = true
}

resource "proxmox_virtual_environment_user_token" "csi" {
  comment    = "Kubernetes CSI"
  token_name = "csi"
  user_id    = proxmox_virtual_environment_user.kubernetes.user_id
}

resource "proxmox_virtual_environment_acl" "csi" {
  token_id = proxmox_virtual_environment_user_token.csi.id
  role_id  = proxmox_virtual_environment_role.csi.role_id

  path      = "/"
  propagate = true
}

output "token" {
  value       = proxmox_virtual_environment_user_token.csi.value
  description = "user token"
  sensitive   = true
}
