variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE Cluster name"
  type        = string
  default     = "min-gke-cluster"
}

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "min-gke-network"
}

variable "machine_type" {
  description = "Machine type for nodes (cost-optimized)"
  type        = string
  default     = "e2-medium"
}

variable "initial_node_count" {
  description = "Initial number of nodes"
  type        = number
  default     = 1
}

variable "min_node_count" {
  description = "Minimum number of nodes in autoscaling"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes in autoscaling"
  type        = number
  default     = 3
}

variable "enable_preemptible_nodes" {
  description = "Use preemptible VMs for cost savings"
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 30
}

variable "enable_shielded_nodes" {
  description = "Enable GKE Shielded Nodes"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.26.13-gke.1000"
}

variable "enable_stackdriver_kubernetes" {
  description = "Enable Google Cloud Logging and Monitoring"
  type        = bool
  default     = true
}
