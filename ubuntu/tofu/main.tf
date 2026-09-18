provider "proxmox" {
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_ENDPOINT= environment variable
  # endpoint = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_USERNAME environment variable
  # username = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_PASSWORD environment variable
  # password = ""
  insecure = false
}

resource "proxmox_virtual_environment_vm" "ubuntu" {
  name        = "ubuntu"
  node_name   = var.node_name
  description = "Ubuntu Server"
  hotplug     = "network,disk,usb,memory"

  cpu {
    cores = 2
    numa  = true
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    import_from = proxmox_download_file.ubuntu_cloud_image.id
    interface   = "virtio0"
    iothread    = true
    discard     = "on"
    size        = var.vm_disk_size
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
        address = var.vm_ip
        gateway = var.vm_gateway
      }
    }

    dns {
      servers = ["1.1.1.1"] # DNS servers
    }

   

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("~/codesenju/kubelab.pub")]
    }
  }

   serial_device { device = "socket" }

  # create lifecycle to ignore changes to keys
  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}


resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name

  url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

  file_name = "jammy-server-cloudimg-amd64.qcow2"
}