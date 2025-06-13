locals {
  private_key_file_path = "./../kubelab.pub" # Change me
  vm_user = "ubuntu"
  vm_password = "ubuntu"
  net = "192.168.0" # First 3 octets of your home network, Change me if you want
  worker_cores  = 6
  worker_memory = 10240
  control_plane_cores  = 2
  control_plane_memory = 4096
  worker_disk_size = 50
  control_plane_disk_size = 25
}