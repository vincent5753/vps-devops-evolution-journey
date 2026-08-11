# ---------- Connection ----------
variable "pve_endpoint" {
  description = "PVE web API address, including the port"
  type        = string
  default     = "https://192.168.1.10:8006/"
}

variable "pve_api_token" {
  description = "Format: OpenTofuUser@pve!provider=<uuid>"
  type        = string
  sensitive   = true
}

variable "pve_insecure" {
  description = "Set to true for self-signed certificates"
  type        = bool
  default     = true
}

variable "pve_node" {
  description = "Node name"
  type        = string
  default     = "pve"
}

# ---------- Template ----------
variable "template_vm_id" {
  description = "VMID of the template built in stage 0"
  type        = number
  default     = 9000
}

variable "cloud_init_snippet" {
  description = "Volume ID of the cloud-init snippet"
  type        = string
  default     = "local:snippets/ubuntu-cloud_init-basic-harden.yaml"
}

# ---------- VM specs ----------
variable "vm_count" {
  description = "How many VMs to create"
  type        = number
  default     = 1
}

variable "vm_name_prefix" {
  type    = string
  default = "tofu-node"
}

variable "vm_id_start" {
  description = "Starting VMID"
  type        = number
  default     = 200
}

variable "vm_cores" {
  type    = number
  default = 2
}

variable "vm_memory" {
  description = "MiB"
  type        = number
  default     = 2048
}

variable "vm_disk_size" {
  description = "GiB"
  type        = number
  default     = 20
}

variable "vm_datastore" {
  description = "Where the VM disk is stored"
  type        = string
  default     = "local-lvm"
}

variable "vm_bridge" {
  type    = string
  default = "vmbr0"
}

variable "agent_timeout" {
  description = "Timeout waiting for qemu-guest-agent to report an IP. cloud-init runs apt upgrade and reboots, so keep this generous"
  type        = string
  default     = "20m"
}
