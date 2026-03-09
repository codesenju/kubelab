locals {
  vm_user     = "ubuntu"
  vm_password = "ubuntu"

  control_plane_cores     = 6
  control_plane_memory    = 8192
  control_plane_disk_size = 60

  starting_ip = 40
  increment   = 1
}
