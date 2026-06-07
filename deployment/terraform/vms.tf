# Ubuntu cloud image, downloaded to each node (bpg imports the disk from it).
resource "proxmox_virtual_environment_download_file" "ubuntu_master" {
  content_type = "iso"
  datastore_id = var.datastore_images
  node_name    = var.pve_node_master
  url          = var.ubuntu_cloud_image_url
  file_name    = "noble-cloudimg-amd64-master.img"
}

resource "proxmox_virtual_environment_download_file" "ubuntu_worker" {
  content_type = "iso"
  datastore_id = var.datastore_images
  node_name    = var.pve_node_worker
  url          = var.ubuntu_cloud_image_url
  file_name    = "noble-cloudimg-amd64-worker.img"
}

# ---------------- master-01 (control plane, laptop PVE node) ----------------
resource "proxmox_virtual_environment_vm" "master" {
  name      = "k3s-master-01"
  node_name = var.pve_node_master
  vm_id     = var.master.vmid
  tags      = ["k3s", "control-plane", "terraform"]

  agent { enabled = true }
  cpu {
    cores = var.master.cores
    type  = "host"
  }
  memory { dedicated = var.master.memory }

  disk {
    datastore_id = var.datastore_master
    interface    = "scsi0"
    size         = var.master.disk_gb
    import_from  = proxmox_virtual_environment_download_file.ubuntu_master.id
  }

  initialization {
    datastore_id = var.datastore_master
    ip_config {
      ipv4 {
        address = var.master.ip
        gateway = var.network_gateway
      }
    }
    user_account {
      username = var.vm_username
      keys     = var.ssh_public_keys
    }
  }

  network_device { bridge = var.network_bridge }
  operating_system { type = "l26" }
}

# ---------------- worker-01 (desktop PVE node, tank + iGPU) ----------------
resource "proxmox_virtual_environment_vm" "worker" {
  name      = "k3s-worker-01"
  node_name = var.pve_node_worker
  vm_id     = var.worker.vmid
  tags      = ["k3s", "worker", "terraform"]

  agent { enabled = true }
  cpu {
    cores = var.worker.cores
    type  = "host" # host CPU type required to expose iGPU features for QSV
  }
  memory {
    dedicated = var.worker.memory  # ceiling, 12G
    floating  = var.worker.balloon # balloon floor, 8G (ballooning 8-12G like the current worker)
  }

  disk {
    datastore_id = var.datastore_worker
    interface    = "scsi0"
    size         = var.worker.disk_gb
    import_from  = proxmox_virtual_environment_download_file.ubuntu_worker.id
  }

  initialization {
    datastore_id = var.datastore_worker
    ip_config {
      ipv4 {
        address = var.worker.ip
        gateway = var.network_gateway
      }
    }
    user_account {
      username = var.vm_username
      keys     = var.ssh_public_keys
    }
  }

  network_device { bridge = var.network_bridge }
  operating_system { type = "l26" }

  # Intel QSV passthrough (only when worker_igpu_pci_id is set).
  dynamic "hostpci" {
    for_each = var.worker_igpu_pci_id == "" ? [] : [1]
    content {
      device = "hostpci0"
      id     = var.worker_igpu_pci_id
      pcie   = true
    }
  }
}
