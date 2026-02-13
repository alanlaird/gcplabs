output "kind1_external_ip" {
  value = google_compute_instance.kind1.network_interface[0].access_config[0].nat_ip
}

output "kind1_internal_ip" {
  value = google_compute_instance.kind1.network_interface[0].network_ip
}

output "kind2_external_ip" {
  value = google_compute_instance.kind2.network_interface[0].access_config[0].nat_ip
}

output "kind2_internal_ip" {
  value = google_compute_instance.kind2.network_interface[0].network_ip
}

output "kind3_external_ip" {
  value = google_compute_instance.kind3.network_interface[0].access_config[0].nat_ip
}

output "kind3_internal_ip" {
  value = google_compute_instance.kind3.network_interface[0].network_ip
}
