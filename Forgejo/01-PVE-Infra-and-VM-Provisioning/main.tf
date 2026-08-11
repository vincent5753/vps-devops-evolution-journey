resource "proxmox_virtual_environment_vm" "node" {
  count = var.vm_count

  name        = format("%s-%02d", var.vm_name_prefix, count.index + 1)
  description = "Managed by OpenTofu"
  tags        = ["opentofu", "ubuntu"]

  node_name = var.pve_node
  vm_id     = var.vm_id_start + count.index

  # Power off immediately on destroy instead of waiting for a graceful
  # shutdown timeout (a VM still running cloud-init won't answer the
  # shutdown signal). Consider setting this to false in production.
  stop_on_destroy = true

  # Full clone from the template built in stage 0
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = true
    # cloud-init runs apt upgrade and then reboots, so the default 15m
    # is often not enough on home bandwidth. Timing out while waiting
    # for an IP would otherwise be misread as a failure.
    timeout = var.agent_timeout
  }

  cpu {
    cores = var.vm_cores
    type  = "host"
  }

  memory {
    dedicated = var.vm_memory
  }

  # The template disk is 3584M; this grows it to vm_disk_size.
  # Note: it can only grow — shrinking errors out.
  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = var.vm_disk_size
    file_format  = "raw"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.vm_datastore # where the cloud-init drive lives

    # References a snippet placed on the node by hand.
    # Note: once user_data_file_id is set, it fully replaces the user-data
    # PVE would generate, so users, SSH keys and hostname all have to be
    # handled by the yaml itself.
    user_data_file_id = var.cloud_init_snippet

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  operating_system {
    type = "l26"
  }

  # No serial_device block is needed: the template already has
  # 'serial0: socket' and the clone inherits it.
  # No lifecycle.ignore_changes either: the MAC is computed anyway, and
  # keeping it would silently swallow changes to vm_bridge.
}
