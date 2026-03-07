variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-west4"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-west4-a"
}

variable "cluster_name" {
  description = "Name prefix for all cluster resources"
  type        = string
  default     = "spot-talos"
}

variable "machine_type" {
  description = "GCP machine type for all nodes"
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "talos_version" {
  description = "Talos version (must match the imported GCP image)"
  type        = string
  default     = "v1.12.4"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}
