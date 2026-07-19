output "wg_vm_name" {
  value = google_compute_instance.wg_vm.name
}

output "wg_new_static_ip" {
  value = google_compute_address.wg_ip.address
}
