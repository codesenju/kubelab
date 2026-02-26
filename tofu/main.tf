terraform {
  backend "s3" {
    bucket = "kubelab-tofu"
    key    = "kubelab.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "https://drives3.iysynergy.com"
    }

    use_path_style = true
    use_lockfile   = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}

provider "proxmox" {
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_ENDPOINT= environment variable
  # endpoint = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_USERNAME environment variable
  # username = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_PASSWORD environment variable
  # password = ""
  insecure = true
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
    # file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    import_from = proxmox_virtual_environment_download_file.ubuntu_cloud_image[0].id
    interface   = "virtio0"
    iothread    = true
    discard     = "on"
    size        = 20
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
      servers = ["${local.net}.15", "1.1.1.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("${local.public_key_file_path}")]
    }
  }

  serial_device { device = "socket" }

  timeout_shutdown_vm = 600

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}

# control-plane Nodes
resource "proxmox_virtual_environment_vm" "k8s_control-plane" {
  count       = 3
  name        = "k8s-control-plane-${count.index + 1}"
  node_name   = local.control_plane_nodes[count.index]
  description = "Kubernetes control-plane Node ${count.index + 1}"
  vm_id       = 4000 + count.index + 1 # Unique VM ID for each control-plane node

  cpu {
    cores = try(local.control_plane_cores_override[count.index], local.control_plane_cores)
  }

  memory {
    dedicated = try(local.control_plane_memory_override[count.index], local.control_plane_memory)
  }


  disk {
    datastore_id = "local-lvm"
    # file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    import_from = local.control_plane_nodes[count.index] == "kubelab-1" ? proxmox_virtual_environment_download_file.ubuntu_cloud_image[0].id : proxmox_virtual_environment_download_file.ubuntu_cloud_image[1].id
    interface   = "virtio0"
    iothread    = true
    discard     = "on"
    size        = local.control_plane_disk_size
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
      servers = ["${local.net}.31", "1.1.1.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("${local.public_key_file_path}")]
    }
  }

  serial_device { device = "socket" }

  timeout_shutdown_vm = 600

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}

# Worker Nodes
resource "proxmox_virtual_environment_vm" "k8s_worker" {
  count     = 3
  name      = "k8s-worker-${count.index + 1}"
  node_name = local.worker_nodes[count.index]
  vm_id     = 5000 + count.index + 1 # Unique VM ID for each worker node

  cpu {
    cores = try(local.worker_cores_override[count.index], local.worker_cores)
    type  = "host" # Use host CPU to resolve minio issue - Fatal glibc error: CPU does not support x86-64-v2
  }

  memory {
    dedicated = try(local.worker_memory_override[count.index], local.worker_memory)
  }


  disk {
    datastore_id = "local-lvm"
    # file_id      = "local:iso/jammy-server-cloudimg-amd64.img"
    import_from = local.worker_nodes[count.index] == "kubelab-1" ? proxmox_virtual_environment_download_file.ubuntu_cloud_image[0].id : proxmox_virtual_environment_download_file.ubuntu_cloud_image[1].id
    interface   = "virtio0"
    iothread    = true
    discard     = "on"
    size        = local.worker_disk_size
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
      servers = ["${local.net}.15", "1.1.1.1"] # DNS servers
    }

    user_account {
      username = local.vm_user
      password = local.vm_password
      keys     = [file("${local.public_key_file_path}")]
    }
  }

  serial_device { device = "socket" }

  timeout_shutdown_vm = 600

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  count        = 2
  content_type = "import"
  datastore_id = "local"
  node_name    = "kubelab-${count.index + 1}"
  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  file_name    = "jammy-server-cloudimg-amd64.qcow2"
}