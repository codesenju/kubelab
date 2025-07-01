# K8s lb
resource "proxmox_virtual_environment_vm" "mng1" {
  name        = "mng1"
  node_name   = "kubelab-2"
  description = "Cloudstack management node"
  vm_id       = 10001

  cpu {
    cores = local.mng_cpu
    type = "host"
  }

  memory {
    dedicated = local.mng_memory
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/noble-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 300
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    # vlan_id = XXX
  }

  operating_system {
    type = "l26" # Linux kernel type
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.101/24"
        gateway = "192.168.0.1"
      }
    }

    dns {
      servers = ["192.168.0.15","1.1.1.1"] # DNS servers
    }

    user_account {
      username = "cloud"
      password = "cloud"
      keys     = [file("../../kubelab.pub")]
    }
  }
  # create lifecycle to ignore changes to keys
  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}

# resource "proxmox_virtual_environment_vm" "kvm1" {
#   name        = "kvm1"
#   node_name   = "kubelab-2"
#   description = "KVM host 1"
#   vm_id       = 10002

#   cpu {
#     cores = local.kvm_cpu
#     type = "host"
#   }

#   memory {
#     dedicated = local.kvm_memory
#   }

#   disk {
#     datastore_id = "local-lvm"
#     file_id      = "local:iso/noble-server-cloudimg-amd64.img"
#     interface    = "virtio0"
#     iothread     = true
#     discard      = "on"
#     size         = 300
#   }

#   network_device {
#     bridge = "vmbr0"
#     model  = "virtio"
#     # vlan_id = XXX
#   }

#   operating_system {
#     type = "l26" # Linux kernel type
#   }

#   initialization {
#     ip_config {
#       ipv4 {
#         address = "192.168.0.100/24"
#         gateway = "192.168.0.1"
#       }
#     }

#     dns {
#       servers = ["192.168.0.15","1.1.1.1"] # DNS servers
#     }

#     user_account {
#       username = "cloud"
#       password = "cloud"
#       keys     = [file("../../kubelab.pub")]
#     }
#   }
#   # create lifecycle to ignore changes to keys
#   lifecycle {
#     ignore_changes = [initialization[0].user_account[0].keys]
#   }
# }

# resource "proxmox_virtual_environment_download_file" "kubelab" {
#   count       = 2
#   content_type = "iso"
#   datastore_id = "local"
#   node_name    = "kubelab-${count.index + 1}"
#   url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
# }