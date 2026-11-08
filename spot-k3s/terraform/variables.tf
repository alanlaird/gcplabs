variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name prefix for all cluster resources"
  type        = string
  default     = "spot-k3s"
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

variable "image" {
  description = "Boot disk OS image"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "ssh_user" {
  description = "SSH username (must match GCP metadata key prefix)"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "../ssh/k3s_key.pub"
}
