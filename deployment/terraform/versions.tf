terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }

  # State lives OFF git. Start with local state on the Semaphore LXC's
  # persistent volume; move to an S3/MinIO backend later if wanted.
  # backend "s3" { ... }
}
