resource "proxmox_virtual_environment_vm" "k8s_worker" {
  count       = var.worker_count
  name        = "k8s-worker-${count.index + local.increment}"
  node_name   = var.proxmox_node
  description = "Kubernetes Worker Node ${count.index + local.increment}"
  vm_id       = var.base_vm_id + count.index + local.increment

  cpu {
    cores = local.worker_cores
  }

  memory {
    dedicated = local.worker_memory
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = local.worker_disk_size
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
      servers = ["${var.network_prefix}.15", "1.1.1.1"]
    }

    user_account {
      username = local.vm_user
      password = local.vm_password
      keys     = [file("../../kubelab.pub")]
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}