resource "google_compute_network" "primary" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "primary" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.primary.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

resource "google_container_cluster" "primary" {
  name               = var.cluster_name
  location           = var.region
  initial_node_count = var.initial_node_count
  network            = google_compute_network.primary.name
  subnetwork         = google_compute_subnetwork.primary.name

  min_master_version = var.kubernetes_version

  # Enable IP aliasing
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Remove default node pool (we'll use node groups instead)
  remove_default_node_pool = true

  # Logging and monitoring
  logging_service    = var.enable_stackdriver_kubernetes ? "logging.googleapis.com/kubernetes" : "none"
  monitoring_service = var.enable_stackdriver_kubernetes ? "monitoring.googleapis.com/kubernetes" : "none"

  # Network policy
  network_policy {
    enabled = true
  }

  # Shielded nodes
  enable_shielded_nodes = var.enable_shielded_nodes

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Cost optimization: enable workload identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name           = "${var.cluster_name}-node-pool"
  location       = var.region
  cluster        = google_container_cluster.primary.name
  node_count     = var.initial_node_count
  version        = var.kubernetes_version

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = var.enable_preemptible_nodes
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Resource requests and limits
    tags = ["gke-node", "min-gke"]
    labels = {
      env     = "dev"
      project = "min-gke"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Limit resource usage
    kubelet_config {
      cpu_manager_policy = "none"
    }
  }
}
