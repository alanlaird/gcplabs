terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

resource "google_compute_network" "kind_network" {
  name                    = "kind-network"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "kind-allow-ssh"
  network = google_compute_network.kind_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kind"]
}

resource "google_compute_firewall" "allow_k8s_api" {
  name    = "kind-allow-k8s-api"
  network = google_compute_network.kind_network.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kind"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "kind-allow-internal"
  network = google_compute_network.kind_network.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_tags = ["kind"]
  target_tags = ["kind"]
}

# Submariner VXLAN tunnels (UDP 4500 cross-cluster, UDP 4800 route agent) and NAT discovery (UDP 4490)
resource "google_compute_firewall" "allow_submariner" {
  name    = "kind-allow-submariner"
  network = google_compute_network.kind_network.name

  allow {
    protocol = "udp"
    ports    = ["4490", "4500", "4800"]
  }

  source_tags = ["kind"]
  target_tags = ["kind"]
}

resource "google_compute_instance" "kind" {
  count        = 3
  name         = "kind${count.index + 1}"
  machine_type = "e2-standard-2"
  tags         = ["kind"]

  scheduling {
    preemptible                 = true
    automatic_restart           = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = google_compute_network.kind_network.name
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_file)}"
  }
}
