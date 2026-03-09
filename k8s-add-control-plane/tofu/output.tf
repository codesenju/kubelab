output "control_plane_ips" {
  description = "IP addresses of the control plane nodes"
  value = {
    for idx, vm in proxmox_virtual_environment_vm.k8s_control_plane :
    vm.name => split("/", vm.initialization[0].ip_config[0].ipv4[0].address)[0]
  }
}
