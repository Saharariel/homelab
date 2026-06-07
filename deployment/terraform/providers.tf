# Single bpg/proxmox provider pointed at one node of the PVE *cluster*.
# A 2-node Proxmox cluster shares one API, so this one endpoint can place VMs
# on either node via each resource's `node_name`.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint  # e.g. https://192.168.50.19:8006/
  api_token = var.proxmox_api_token # e.g. terraform@pve!iac=<uuid-secret>
  insecure  = var.proxmox_insecure  # true while using the PVE self-signed cert

  # Used by the provider for operations that need SSH (image import, etc.).
  ssh {
    agent    = true
    username = "root"
  }
}
