output "control_plane_ip" {
  value       = google_compute_address.control_plane.address
  description = "Control plane static public IP (stable across MIG restarts)"
}

output "worker_ips_cmd" {
  value       = "gcloud compute instances list --project=${var.project_id} --filter=\"name~'^${var.cluster_name}-worker'\" --format='value(EXTERNAL_IP)'"
  description = "gcloud command to list current worker IPs (managed by MIG)"
}

output "talosctl_endpoint" {
  value       = "talosctl --nodes ${google_compute_address.control_plane.address} --endpoints ${google_compute_address.control_plane.address} --talosconfig talos/talosconfig"
  description = "Base talosctl command for this cluster"
}
