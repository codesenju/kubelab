provider "proxmox" {
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_ENDPOINT= environment variable
  # endpoint = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_USERNAME environment variable
  # username = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_PASSWORD environment variable
  # password = ""
  insecure  = true
}

# K8s lb
resource "proxmox_virtual_environment_vm" "ubuntu" {
  name        = "ubuntu"
  node_name   = "kubelab-1"
  description = "Ubuntu Server"
  vm_id       = 2001 # Unique VM ID for the load balancer

  cpu {
    cores = 4
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 80
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
        address = "192.168.0.31/24" # Static IP for the load balancer
        gateway = "192.168.0.1"
      }
    }

    dns {
      servers = ["192.168.0.15","1.1.1.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("../../kubelab.pub")]
    }
  }
  # create lifecycle to ignore changes to keys
  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}


# resource "proxmox_virtual_environment_download_file" "kubelab" {
#   count       = 2
#   content_type = "iso"
#   datastore_id = "local"
#   node_name    = "kubelab-${count.index + 1}"
#   url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
# }