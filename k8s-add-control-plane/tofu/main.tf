resource "proxmox_virtual_environment_vm" "k8s_control_plane" {
  count       = var.control_plane_count
  name        = "k8s-control-plane-${count.index + local.increment}"
  node_name   = var.proxmox_node
  description = "Kubernetes Control Plane Node ${count.index + local.increment}"
  vm_id       = var.vm_id != null ? var.vm_id + count.index : var.base_vm_id + count.index + local.increment

  cpu {
    cores = local.control_plane_cores
  }

  memory {
    dedicated = local.control_plane_memory
  }

  disk {
    datastore_id = "local-lvm"
    file_id     = "local:import/jammy-server-cloudimg-amd64.qcow2"
    interface   = "virtio0"
    iothread    = true
    discard     = "on"
    size        = local.control_plane_disk_size
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.network_prefix}.${local.starting_ip + count.index + 1}/24"
        gateway = "${var.network_prefix}.1"
      }
    }

    dns {
      servers = ["${var.network_prefix}.31", "1.1.1.1"]
    }

    user_account {
      username = local.vm_user
      password = local.vm_password
      keys     = [file("~/codesenju/kubelab.pub")]
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}
