variable "proxmox_node" {
  type        = string
  description = "Proxmox node name where VMs will be created"
}

variable "control_plane_count" {
  type        = number
  description = "Number of control plane nodes to add"
  default     = 1
}

variable "base_vm_id" {
  type        = number
  description = "Base VM ID for control plane nodes"
  default     = 4000
}

variable "network_prefix" {
  type        = string
  description = "First 3 octets of the network (e.g., 192.168.0)"
  default     = "192.168.0"
}

variable "vm_id" {
  type        = number
  description = "Specific VM ID for the control plane node (overrides base_vm_id when set)"
  default     = null
}
