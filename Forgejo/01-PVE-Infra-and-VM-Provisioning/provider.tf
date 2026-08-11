terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Check registry.terraform.io/providers/bpg/proxmox for the latest version
      version = ">= 0.60"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = var.pve_insecure

  # The ssh {} block is intentionally omitted.
  # The cloud-init snippet is placed on the node by hand, so the provider
  # never needs to upload anything — and therefore never needs SSH access.
  #
  # Only uncomment the block below if you later switch to managing the
  # snippet with proxmox_virtual_environment_file:
  #
  # ssh {
  #   agent    = true
  #   username = "root"
  # }
}
