terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }

  # backend "s3" { ... }  # optional remote state
}
