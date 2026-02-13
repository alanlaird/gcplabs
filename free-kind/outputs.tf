output "kind_external_ip" {
  value = google_compute_instance.kind.network_interface[0].access_config[0].nat_ip
}

output "kind_internal_ip" {
  value = google_compute_instance.kind.network_interface[0].network_ip
}

output "kindspot_external_ip" {
  value = google_compute_instance.kindspot.network_interface[0].access_config[0].nat_ip
}

output "kindspot_internal_ip" {
  value = google_compute_instance.kindspot.network_interface[0].network_ip
}
