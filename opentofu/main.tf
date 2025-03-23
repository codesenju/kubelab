provider "proxmox" {
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_ENDPOINT= environment variable
  # endpoint      = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_USERNAME environment variable
  # username = ""
  # TODO: use terraform variable or remove the line, and use PROXMOX_VE_PASSWORD environment variable
  # password = ""
  insecure  = true
}

# Master Nodes
resource "proxmox_virtual_environment_vm" "k8s_master" {
  count       = 2
  name        = "k8s-master-${count.index + 1}"
  node_name   = "kubelab-${count.index + 1}"
  description = "Kubernetes Master Node ${count.index + 1}"
  vm_id       = 4000 + count.index + 1 # Unique VM ID for each master node

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }


  disk {
    datastore_id = "local-lvm"
    # file_id      = proxmox_virtual_environment_download_file.kubelab[1].id
    file_id      = "local:iso/noble-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }


  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    vlan_id = 100
  }

  operating_system {
    type = "l26" # Linux kernel type
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.${40 + count.index + 1}/24" # Static IP for master nodes
        gateway = "192.168.100.1"
      }
    }

    dns {
      servers = ["192.168.100.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("./../kubelab.pub")]
    }
  }
}

# Worker Nodes
resource "proxmox_virtual_environment_vm" "k8s_worker" {
  count       = 2
  name        = "k8s-worker-${count.index + 1}"
  node_name   = "kubelab-${count.index + 1}"
  description = "Kubernetes Worker Node ${count.index + 1}"
  vm_id       = 5000 + count.index + 1 # Unique VM ID for each worker node

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }


  disk {
    datastore_id = "local-lvm"
    # file_id      = proxmox_virtual_environment_download_file.kubelab[0].id
    file_id      = "local:iso/noble-server-cloudimg-amd64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    vlan_id = 100
  }

  operating_system {
    type = "l26" # Linux kernel type
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.${50 + count.index + 1}/24" # Static IP for worker nodes
        gateway = "192.168.100.1"
      }
    }

    dns {
      servers = ["192.168.100.1"] # DNS servers
    }

    user_account {
      username = "ubuntu"
      password = "ubuntu"
      keys     = [file("./../kubelab.pub")]
    }
  }
}

# resource "proxmox_virtual_environment_download_file" "kubelab" {
#   count       = 2
#   content_type = "iso"
#   datastore_id = "local"
#   node_name    = "kubelab-${count.index + 1}"
#   url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
# }