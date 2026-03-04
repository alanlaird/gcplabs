variable "project" {
  description = "GCP project ID"
  type        = string
  default     = "sandbox-485223"
}

variable "region" {
  description = "GCP region (free tier eligible)"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-west1-b"
}

variable "ssh_user" {
  description = "SSH username for instances"
  type        = string
  default     = "laird"
}

variable "ssh_pub_key_file" {
  description = "Path to SSH public key"
  type        = string
  default     = "id_gcp.pub"
}

variable "ssh_priv_key_file" {
  description = "Path to SSH private key"
  type        = string
  default     = "id_gcp"
}


