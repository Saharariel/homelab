# ---------- Proxmox connection ----------
variable "proxmox_endpoint" {
  type        = string
  description = "PVE API endpoint, e.g. https://192.168.50.19:8006/"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "API token: user@realm!tokenid=secret (injected by the orchestrator)"
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

# ---------- Cluster node placement ----------
# Two PVE nodes in one cluster. master on the (encrypted) laptop node,
# worker on the desktop node that owns the tank ZFS pool + the GPU.
variable "pve_node_master" {
  type        = string
  description = "PVE node name hosting the control plane (the laptop)."
}

variable "pve_node_worker" {
  type        = string
  description = "PVE node name hosting the worker (the i7 desktop with tank + iGPU)."
}

# Datastore that backs each VM's disk. Point these at an ENCRYPTED ZFS dataset
# on each node (e.g. local-zfs on an encrypted pool) so VM disks are at-rest encrypted.
variable "datastore_master" {
  type    = string
  default = "local-lvm" # node SSD (NOT the tank HDD pool); master's is the laptop's encrypted NVMe
}
variable "datastore_worker" {
  type    = string
  default = "local-lvm" # node SSD (NOT the tank HDD pool); master's is the laptop's encrypted NVMe
}

# Datastore that holds the downloaded cloud image / ISOs (snippets-capable).
variable "datastore_images" {
  type    = string
  default = "local"
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
    ip      = string # CIDR, e.g. 192.168.50.19/24
  })
  default = {
    vmid = 110, cores = 2, memory = 4096, disk_gb = 40, ip = "192.168.50.19/24"
  }
}

variable "worker" {
  type = object({
    vmid    = number
    cores   = number
    memory  = number # balloon ceiling (max), MB
    balloon = number # balloon floor (min guaranteed), MB — frees idle RAM to the host
    disk_gb = number
    ip      = string
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

# ---------- GPU passthrough (worker only, Intel QSV for Jellyfin) ----------
# PCI id of the iGPU on the desktop, e.g. "0000:00:02.0". Find with `lspci -nn | grep VGA`.
variable "worker_igpu_pci_id" {
  type        = string
  default     = ""
  description = "Leave empty to skip passthrough; set to the iGPU PCI id to enable QSV."
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
