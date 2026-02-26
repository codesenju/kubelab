locals {
  public_key_file_path    = "~/codesenju/kubelab.pub" # Change me
  vm_user                 = "ubuntu"
  vm_password             = "ubuntu"
  net                     = "192.168.0" # First 3 octets of your home network, Change me if you want
  worker_cores            = 6
  worker_memory           = 4096
  control_plane_cores     = 6
  control_plane_memory    = 4096
  worker_disk_size        = 80
  control_plane_disk_size = 50

  # Proxmox node assignment for each VM
  # Control plane nodes (3 nodes)
  control_plane_nodes = [
    "kubelab-1", # k8s-control-plane-1
    "kubelab-1", # k8s-control-plane-2
    "kubelab-2", # k8s-control-plane-3
  ]

  # Worker nodes (3 nodes)
  worker_nodes = [
    "kubelab-1", # k8s-worker-1
    "kubelab-1", # k8s-worker-2
    "kubelab-2", # k8s-worker-3
  ]

  # Per-worker CPU and memory overrides (indexed by worker number - 1)
  # Uncomment and modify these arrays to override default resources per worker
  # If not specified, defaults to worker_cores and worker_memory above
  # Note: kubelab-1 and kubelab-2 both max at 6 vcpus per VM
  worker_cores_override = [
    20, # k8s-worker-1 on kubelab-1 (max 20 CPUs)
    20, # k8s-worker-2 on kubelab-1 (max 20 CPUs)
    6,  # k8s-worker-3 on kubelab-2 (max 6 CPUs)
  ]

  worker_memory_override = [
    16384, # k8s-worker-1 on kubelab-1
    16384, # k8s-worker-2 on kubelab-1
    20480, # k8s-worker-3 on kubelab-2
  ]

  # Per-control-plane CPU and memory overrides (indexed by control plane number - 1)
  # Uncomment and modify these arrays to override default resources per control plane
  # If not specified, defaults to control_plane_cores and control_plane_memory above
  # Note: kubelab-1 and kubelab-2 both max at 6 vcpus per VM
  control_plane_cores_override = [
    12, # k8s-control-plane-1 on kubelab-1 (max 20 CPUs)
    12, # k8s-control-plane-2 on kubelab-1 (max 20 CPUs)
    6,  # k8s-control-plane-3 on kubelab-2 (max 6 CPUs)
  ]

  control_plane_memory_override = [
    12288, # k8s-control-plane-1 on kubelab-1
    12288, # k8s-control-plane-2 on kubelab-1
    12288, # k8s-control-plane-3 on kubelab-2
  ]
}