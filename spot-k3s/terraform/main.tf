resource "google_compute_network" "k3s" {
  name                    = "${var.cluster_name}-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "k3s" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.k3s.id
}

# Allow SSH from anywhere
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.cluster_name}-allow-ssh"
  network = google_compute_network.k3s.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-node"]
}

# Allow k3s API server from anywhere
resource "google_compute_firewall" "allow_k3s_api" {
  name    = "${var.cluster_name}-allow-k3s-api"
  network = google_compute_network.k3s.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-node"]
}

# Allow all traffic between cluster nodes
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.k3s.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["k3s-node"]
}

# Allow NodePort services
resource "google_compute_firewall" "allow_nodeport" {
  name    = "${var.cluster_name}-allow-nodeport"
  network = google_compute_network.k3s.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-node"]
}

resource "google_compute_instance" "master" {
  name         = "${var.cluster_name}-master"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["k3s-node"]

  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
    preemptible         = true
  }

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k3s.id
    access_config {} # ephemeral public IP
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_file)}"
  }
}

resource "google_compute_instance" "workers" {
  count        = var.worker_count
  name         = "${var.cluster_name}-worker-${count.index}"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["k3s-node"]

  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
    preemptible         = true
  }

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k3s.id
    access_config {} # ephemeral public IP
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_file)}"
  }
}

# Generate Ansible inventory after instances are created
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    master_public_ip  = google_compute_instance.master.network_interface[0].access_config[0].nat_ip
    master_private_ip = google_compute_instance.master.network_interface[0].network_ip
    worker_public_ips = [for w in google_compute_instance.workers : w.network_interface[0].access_config[0].nat_ip]
    ssh_user          = var.ssh_user
    ssh_key           = abspath("${path.module}/../ssh/k3s_key")
  })
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
}
