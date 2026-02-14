output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
  sensitive   = true
}

output "region" {
  value       = var.region
  description = "GCP region"
}

output "project_id" {
  value       = var.project_id
  description = "GCP Project ID"
}

output "network_name" {
  value       = google_compute_network.primary.name
  description = "VPC Network name"
}

output "subnet_name" {
  value       = google_compute_subnetwork.primary.name
  description = "Subnet name"
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "Cluster endpoint"
}

output "ca_certificate" {
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  description = "Cluster CA certificate"
  sensitive   = true
}

output "kubeconfig_path_instruction" {
  value       = "Run: gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region=${var.region} --project=${var.project_id}"
  description = "Command to get kubeconfig"
}
