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
resource "proxmox_virtual_environment_vm" "k8s_lb" {
  name        = "k8s-lb"
  node_name   = "kubelab-1"
  description = "Kubernetes Load Balancer"
  vm_id       = 4000 # Unique VM ID for the load balancer

  cpu {
    units = 512
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
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
        address = "192.168.0.40/24" # Static IP for the load balancer
        gateway = "192.168.0.1"
      }
    }

    dns {
      servers = ["192.168.0.15","1.1.1.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("./../kubelab.pub")]
    }
  }

  serial_device { device = "socket"}

  # create lifecycle to ignore changes to keys
  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}

# control-plane Nodes
resource "proxmox_virtual_environment_vm" "k8s_control-plane" {
  count       = 3
  name        = "k8s-control-plane-${count.index + 1}"
  node_name   = "kubelab-1"
  description = "Kubernetes control-plane Node ${count.index + 1}"
  vm_id       = 4000 + count.index + 1 # Unique VM ID for each control-plane node

  cpu {
    cores = local.control_plane_cores
  }

  memory {
    dedicated = local.control_plane_memory
  }


  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = local.control_plane_disk_size
  }


  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    # vlan_id = 100
  }

  operating_system {
    type = "l26" # Linux kernel type
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${local.net}.${40 + count.index + 1}/24" # Static IP for control-plane nodes
        gateway = "${local.net}.1"
      }
    }

    dns {
      servers = ["${local.net}.15","1.1.1.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("${local.private_key_file_path}")]
    }
  }

  serial_device { device = "socket"}

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}

# Worker Nodes
resource "proxmox_virtual_environment_vm" "k8s_worker" {
  count       = 3
  name        = "k8s-worker-${count.index + 1}"
  node_name   = "kubelab-1"
  description = "Kubernetes Worker Node ${count.index + 1}"
  vm_id       = 5000 + count.index + 1 # Unique VM ID for each worker node

  cpu {
    cores = local.worker_cores
    type = "host" # Use host CPU to resolve minio issue - Fatal glibc error: CPU does not support x86-64-v2
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
    # vlan_id = 100
  }

  operating_system {
    type = "l26" # Linux kernel type
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${local.net}.${50 + count.index + 1}/24" # Static IP for worker nodes
        gateway = "${local.net}.1"
      }
    }

    dns {
      servers = ["${local.net}.15","1.1.1.1"] # DNS servers
    }

    user_account {
      username = local.vm_user
      password = local.vm_password
      keys     = [file("${local.private_key_file_path}")]
    }
  }

  serial_device { device = "socket"}

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