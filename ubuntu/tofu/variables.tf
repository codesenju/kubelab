variable "node_name" {
  description = "The name of the Proxmox node where the VM will be created."
  type        = string
}

variable "vm_disk_size" {
  description = "The size of the VM disk in GB."
  type        = number
}

variable "vm_gateway" {
  description = "The gateway IP address for the VM."
  type        = string
}

variable "vm_ip" {
  description = "The IP address of the VM."
  type        = string
}
