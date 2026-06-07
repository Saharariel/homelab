# ---------- Proxmox connection ----------
variable "proxmox_endpoint" {
  type        = string
  description = "PVE API endpoint, e.g. https://<node>:8006/"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "API token in the form user@realm!tokenid=secret."
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

# ---------- Cluster node placement ----------
variable "pve_node_master" {
  type        = string
  description = "PVE node name hosting the control plane."
}

variable "pve_node_worker" {
  type        = string
  description = "PVE node name hosting the worker (with the iGPU)."
}

# VM disks are placed on each node's local SSD datastore.
variable "datastore_master" {
  type    = string
  default = "local-lvm"
}
variable "datastore_worker" {
  type    = string
  default = "local-lvm"
}

variable "datastore_images" {
  type        = string
  default     = "local"
  description = "Datastore holding the downloaded cloud image."
}

# ---------- VM image ----------
variable "ubuntu_cloud_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# ---------- VM specs ----------
variable "master" {
  type = object({
    vmid    = number
    cores   = number
    memory  = number # MB
    disk_gb = number
    ip      = string # CIDR
  })
  default = {
    vmid = 110, cores = 2, memory = 4096, disk_gb = 40, ip = "192.168.50.19/24"
  }
}

variable "worker" {
  type = object({
    vmid    = number
    cores   = number
    memory  = number # balloon ceiling, MB
    balloon = number # balloon floor, MB
    disk_gb = number
    ip      = string # CIDR
  })
  default = {
    vmid = 111, cores = 8, memory = 12288, balloon = 8192, disk_gb = 60, ip = "192.168.50.18/24"
  }
}

variable "network_gateway" {
  type    = string
  default = "192.168.50.1"
}
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

# ---------- GPU passthrough (worker) ----------
variable "worker_igpu_pci_id" {
  type        = string
  default     = ""
  description = "iGPU PCI id (lspci -nn | grep VGA). Empty disables passthrough."
}

# ---------- Cloud-init access ----------
variable "vm_username" {
  type    = string
  default = "ubuntu"
}
variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys injected into the VMs for Ansible access."
}
