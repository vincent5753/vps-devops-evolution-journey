output "vm_summary" {
  description = "List of the VMs that were created"
  value = {
    for vm in proxmox_virtual_environment_vm.node :
    vm.name => {
      vm_id = vm.vm_id
      node  = vm.node_name
    }
  }
}

output "vm_ipv4" {
  description = "IPv4 address of each VM. Only readable once qemu-guest-agent is up, so it may be empty right after apply"
  value = {
    for vm in proxmox_virtual_environment_vm.node :
    vm.name => try(vm.ipv4_addresses, [])
  }
}
