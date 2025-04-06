locals {
  vm_user     = "ubuntu"
  vm_password = "ubuntu"
  
  worker_cores  = 4
  worker_memory = 8192
  worker_disk_size = 20

  starting_ip = 56
  increment = 5
}