variable "proxmox_node" {
  type        = string
  description = "Proxmox node name where VMs will be created"
}

variable "worker_count" {
  type        = number
  description = "Number of worker nodes to add"
  default     = 1
}

variable "base_vm_id" {
  type        = number
  description = "Base VM ID for worker nodes"
  default     = 6000
}

variable "network_prefix" {
  type        = string
  description = "First 3 octets of the network (e.g., 192.168.0)"
  default     = "192.168.0"
}