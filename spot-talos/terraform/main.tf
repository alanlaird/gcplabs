locals {
  talos_image_name = "talos-${replace(var.talos_version, ".", "-")}-gcp-amd64"
}

# Reference the Talos image imported by `make image`
data "google_compute_image" "talos" {
  name    = local.talos_image_name
  project = var.project_id
}

resource "google_compute_network" "talos" {
  name                    = "${var.cluster_name}-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "talos" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.talos.id
}

# Talos API (management via talosctl)
resource "google_compute_firewall" "allow_talos_api" {
  name    = "${var.cluster_name}-allow-talos-api"
  network = google_compute_network.talos.name

  allow {
    protocol = "tcp"
    ports    = ["50000"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["talos-node"]
}

# Kubernetes API server
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "${var.cluster_name}-allow-k8s-api"
  network = google_compute_network.talos.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["talos-node"]
}

# All traffic between cluster nodes (etcd, Flannel VXLAN, Talos internal)
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.talos.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["talos-node"]
}

# NodePort services
resource "google_compute_firewall" "allow_nodeport" {
  name    = "${var.cluster_name}-allow-nodeport"
  network = google_compute_network.talos.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["talos-node"]
}

# Static IP for the control plane — stable across MIG-initiated restarts so the
# Talos/K8s endpoint embedded in machine configs never needs to change.
resource "google_compute_address" "control_plane" {
  name   = "${var.cluster_name}-cp-ip"
  region = var.region
}

# TCP health check on the Talos API port.  MIG uses this to detect unhealthy
# (e.g. preempted) instances and replace them automatically.
resource "google_compute_health_check" "talos_api" {
  name               = "${var.cluster_name}-talos-hc"
  check_interval_sec = 30
  timeout_sec        = 10
  healthy_threshold  = 1
  unhealthy_threshold = 3

  tcp_health_check {
    port = 50000
  }
}

# ── Control plane ─────────────────────────────────────────────────────────────

resource "google_compute_instance_template" "control_plane" {
  name_prefix  = "${var.cluster_name}-cp-"
  machine_type = var.machine_type
  tags         = ["talos-node"]

  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
    preemptible         = true
  }

  disk {
    source_image = data.google_compute_image.talos.self_link
    disk_size_gb = var.disk_size_gb
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.talos.id
    # Pin the reserved static IP so the Talos/K8s endpoint never changes.
    access_config {
      nat_ip = google_compute_address.control_plane.address
    }
  }

  # Talos reads user-data from GCP instance metadata on first boot and
  # self-configures without needing talosctl apply-config.
  # The file is absent on the very first `terraform apply` (before genconfig
  # runs); the second apply embeds it and MIG rolls out a fresh instance.
  metadata = fileexists("${path.module}/../talos/controlplane.yaml") ? {
    user-data = file("${path.module}/../talos/controlplane.yaml")
  } : {}

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "control_plane" {
  name               = "${var.cluster_name}-cp-mig"
  zone               = var.zone
  base_instance_name = "${var.cluster_name}-cp"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.control_plane.id
  }

  # Replace unhealthy instances automatically (e.g. after spot preemption).
  # initial_delay_sec gives a fresh instance enough time to boot and install
  # before the health check starts evaluating it.
  auto_healing_policies {
    health_check      = google_compute_health_check.talos_api.id
    initial_delay_sec = 300
  }

  # When the template changes (e.g. after genconfig embeds user-data), roll out
  # replacement instances automatically.
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_unavailable_fixed = 1
  }
}

# ── Workers ───────────────────────────────────────────────────────────────────

resource "google_compute_instance_template" "workers" {
  name_prefix  = "${var.cluster_name}-worker-"
  machine_type = var.machine_type
  tags         = ["talos-node"]

  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
    preemptible         = true
  }

  disk {
    source_image = data.google_compute_image.talos.self_link
    disk_size_gb = var.disk_size_gb
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.talos.id
    access_config {} # ephemeral public IP
  }

  metadata = fileexists("${path.module}/../talos/worker.yaml") ? {
    user-data = file("${path.module}/../talos/worker.yaml")
  } : {}

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "workers" {
  name               = "${var.cluster_name}-worker-mig"
  zone               = var.zone
  base_instance_name = "${var.cluster_name}-worker"
  target_size        = var.worker_count

  version {
    instance_template = google_compute_instance_template.workers.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.talos_api.id
    initial_delay_sec = 300
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_unavailable_fixed = 1
  }
}
