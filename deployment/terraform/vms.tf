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

resource "proxmox_virtual_environment_vm" "worker" {
  name      = "k3s-worker-01"
  node_name = var.pve_node_worker
  vm_id     = var.worker.vmid
  tags      = ["k3s", "worker", "terraform"]

  agent { enabled = true }

  # q35 + OVMF are required for the iGPU PCIe passthrough below.
  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = var.worker.cores
    type  = "host"
  }
  memory {
    dedicated = var.worker.memory
    floating  = var.worker.balloon
  }

  disk {
    datastore_id = var.datastore_worker
    interface    = "scsi0"
    size         = var.worker.disk_gb
    import_from  = proxmox_virtual_environment_download_file.ubuntu_worker.id
  }

  efi_disk {
    datastore_id      = var.datastore_worker
    type              = "4m"
    pre_enrolled_keys = true
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

  dynamic "hostpci" {
    for_each = var.worker_igpu_pci_id == "" ? [] : [1]
    content {
      device = "hostpci0"
      id     = var.worker_igpu_pci_id
      pcie   = true
    }
  }
}
