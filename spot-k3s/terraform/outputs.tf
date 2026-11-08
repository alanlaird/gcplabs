output "master_public_ip" {
  value       = google_compute_instance.master.network_interface[0].access_config[0].nat_ip
  description = "Master node public IP"
}

output "master_private_ip" {
  value       = google_compute_instance.master.network_interface[0].network_ip
  description = "Master node private IP (for intra-cluster communication)"
}

output "worker_public_ips" {
  value       = [for w in google_compute_instance.workers : w.network_interface[0].access_config[0].nat_ip]
  description = "Worker node public IPs"
}

output "ssh_user" {
  value       = var.ssh_user
  description = "SSH username"
}

output "ssh_command" {
  value       = "ssh -i ssh/k3s_key ${var.ssh_user}@${google_compute_instance.master.network_interface[0].access_config[0].nat_ip}"
  description = "SSH command to access the master node"
}
