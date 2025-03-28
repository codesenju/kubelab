locals {
  private_key_file_path = "./../kubelab.pub" # Change me
  vm_user = "ubuntu"
  vm_password = "ubuntu"
  net = "192.168.0" # First 3 octets of your home network, Change me if you want

  worker_cores  = 6
  worker_memory = 8192
  control_plane_cores  = 4
  control_plane_memory = 6144
  worker_disk_size = 50
  control_plane_disk_size = 25
}