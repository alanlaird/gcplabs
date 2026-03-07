.PHONY: help prereqs image init up down kubeconfig status clean recover history stop_billing

TALOS_VERSION   := v1.12.4
# Default schematic: base Talos image with no extensions.
# Obtain a custom schematic ID at https://factory.talos.dev
TALOS_SCHEMATIC := 376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba
CLUSTER_NAME    := spot-talos
TALOS_DIR       := talos
KUBECONFIG      := kubeconfig.yaml
IMAGE_NAME      := talos-$(subst .,-,$(TALOS_VERSION))-gcp-amd64

# Read config from tfvars
PROJECT_ID   := $(shell grep '^project_id'   terraform/terraform.tfvars 2>/dev/null | awk -F'"' '{print $$2}')
REGION       := $(shell grep '^region'       terraform/terraform.tfvars 2>/dev/null | awk -F'"' '{print $$2}')
ZONE         := $(shell grep '^zone'         terraform/terraform.tfvars 2>/dev/null | awk -F'"' '{print $$2}')
MACHINE_TYPE := $(shell grep '^machine_type' terraform/terraform.tfvars 2>/dev/null | awk -F'"' '{print $$2}')
DISK_SIZE_GB := $(shell grep '^disk_size_gb' terraform/terraform.tfvars 2>/dev/null | awk '{print $$3}')

help:
	@echo "spot-talos — Talos Linux cluster on GCP spot instances (MIG-managed)"
	@echo ""
	@echo "  make image      Import Talos GCP image (once per project/version)"
	@echo "  make up         Create cluster (terraform + talos bootstrap)"
	@echo "  make down       Destroy all GCP resources"
	@echo "  make recover    Re-fetch kubeconfig after MIG replaces nodes"
	@echo "  make kubeconfig Re-fetch kubeconfig from control plane"
	@echo "  make status     Show node and pod status"
	@echo "  make stop_billing Destroy everything including image and GCS bucket"
	@echo "  make prereqs    Check required tools"
	@echo "  make history    Show spot preemption history"
	@echo "  make clean      Remove local state files"
	@echo ""
	@echo "MIG auto-healing: preempted instances are replaced automatically."
	@echo "Nodes self-configure from machine config embedded in instance metadata."
	@echo ""
	@echo "First-time setup:"
	@echo "  1. cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
	@echo "  2. Edit terraform/terraform.tfvars with your GCP project ID"
	@echo "  3. make image"
	@echo "  4. make up"

prereqs:
	@command -v terraform  >/dev/null 2>&1 || { echo "✗ terraform not found:   brew install terraform"; exit 1; }
	@command -v talosctl   >/dev/null 2>&1 || { echo "✗ talosctl not found:    brew install siderolabs/tap/talosctl"; exit 1; }
	@command -v gcloud     >/dev/null 2>&1 || { echo "✗ gcloud not found:      brew install google-cloud-sdk"; exit 1; }
	@command -v jq         >/dev/null 2>&1 || { echo "✗ jq not found:          brew install jq"; exit 1; }
	@test -f terraform/terraform.tfvars || { echo "✗ terraform/terraform.tfvars not found — copy from terraform.tfvars.example"; exit 1; }
	@echo "✓ All prerequisites satisfied"

# Import the Talos disk image into GCP (one-time per project/version).
# Downloads the raw disk image from GitHub, uploads to GCS, and creates a
# compute image. Skips if the image already exists.
image:
	@test -n "$(PROJECT_ID)" || { echo "✗ project_id not found in terraform/terraform.tfvars"; exit 1; }
	@if gcloud compute images describe $(IMAGE_NAME) --project=$(PROJECT_ID) >/dev/null 2>&1; then \
	  echo "✓ Image $(IMAGE_NAME) already exists — skipping import"; \
	else \
	  echo "→ Importing Talos $(TALOS_VERSION) image to GCP project $(PROJECT_ID) ..." && \
	  BUCKET=$(PROJECT_ID)-talos-images && \
	  gsutil mb -p $(PROJECT_ID) gs://$$BUCKET/ 2>/dev/null || true && \
	  echo "  downloading gcp-amd64.raw.tar.gz from Talos Image Factory ..." && \
	  curl -fL -o /tmp/$(IMAGE_NAME).raw.tar.gz \
	    https://factory.talos.dev/image/$(TALOS_SCHEMATIC)/$(TALOS_VERSION)/gcp-amd64.raw.tar.gz && \
	  echo "  uploading to gs://$$BUCKET/ ..." && \
	  gsutil cp /tmp/$(IMAGE_NAME).raw.tar.gz gs://$$BUCKET/$(IMAGE_NAME).raw.tar.gz && \
	  echo "  creating compute image $(IMAGE_NAME) ..." && \
	  gcloud compute images create $(IMAGE_NAME) \
	    --source-uri=gs://$$BUCKET/$(IMAGE_NAME).raw.tar.gz \
	    --project=$(PROJECT_ID) && \
	  rm -f /tmp/$(IMAGE_NAME).raw.tar.gz && \
	  echo "✓ Image $(IMAGE_NAME) ready"; \
	fi

init:
	cd terraform && terraform init

# Create cluster using a two-phase terraform apply:
#
#   Phase 1 — provision infrastructure (network, static IP, MIGs).
#             Nodes boot into Talos maintenance mode (no machine config yet).
#
#   genconfig — generate Talos machine configs using the reserved static IP.
#
#   Phase 2 — embed configs in instance templates as user-data metadata.
#             MIG detects template change and replaces instances; new instances
#             self-configure on boot without needing talosctl apply-config.
#
# After phase 2, _bootstrap just waits for the Talos API and bootstraps etcd.
# MIG auto-healing handles all future spot preemptions automatically.
up: init
	@echo "→ Phase 1: provisioning infrastructure ..."
	cd terraform && terraform apply -auto-approve
	@$(MAKE) _genconfig
	@echo "→ Phase 2: embedding machine configs in instance templates ..."
	cd terraform && terraform apply -auto-approve
	@$(MAKE) _bootstrap
	@$(MAKE) kubeconfig
	@echo ""
	@echo "✓ Cluster is up"
	@echo "  export KUBECONFIG=$(PWD)/$(KUBECONFIG)"
	@echo "  kubectl get nodes"

# Generate Talos machine configs from the reserved static control plane IP.
# Idempotent: skips if configs already exist and nodes are reachable.
_genconfig:
	@CTRL_IP=$$(cd terraform && terraform output -raw control_plane_ip) && \
	mkdir -p $(TALOS_DIR) && \
	if [ -f $(TALOS_DIR)/talosconfig ] && \
	   talosctl version --nodes $$CTRL_IP --endpoints $$CTRL_IP \
	     --talosconfig $(TALOS_DIR)/talosconfig >/dev/null 2>&1; then \
	  echo "→ Talos configs exist and nodes are reachable — skipping genconfig"; \
	else \
	  echo "→ Generating Talos config for https://$$CTRL_IP:6443 ..." && \
	  talosctl gen config $(CLUSTER_NAME) https://$$CTRL_IP:6443 \
	    --output-dir $(TALOS_DIR) --force && \
	  echo "✓ Configs written to $(TALOS_DIR)/"; \
	fi

# Wait for the Talos API (nodes self-configure from user-data metadata after
# MIG launches them) then bootstrap etcd.  Idempotent: already-bootstrapped
# is not an error.
_bootstrap:
	@CTRL_IP=$$(cd terraform && terraform output -raw control_plane_ip) && \
	echo "→ Waiting for Talos API on $$CTRL_IP (nodes self-configure from metadata) ..." && \
	i=0; while ! talosctl version \
	    --nodes $$CTRL_IP --endpoints $$CTRL_IP \
	    --talosconfig $(TALOS_DIR)/talosconfig >/dev/null 2>&1; do \
	  i=$$((i+1)); \
	  [ $$i -ge 90 ] && { echo "✗ Timed out waiting for Talos API"; exit 1; }; \
	  echo "  attempt $$i/90, retrying in 10s ..."; sleep 10; \
	done && \
	echo "→ Bootstrapping etcd ..." && \
	i=0; while true; do \
	  out=$$(talosctl bootstrap \
	    --nodes $$CTRL_IP --endpoints $$CTRL_IP \
	    --talosconfig $(TALOS_DIR)/talosconfig 2>&1); \
	  rc=$$?; \
	  [ $$rc -eq 0 ] && { echo "✓ etcd bootstrapped"; break; }; \
	  echo "$$out" | grep -qE "not available yet|already initialized|AlreadyExists" || { echo "✗ bootstrap: $$out"; exit 1; }; \
	  echo "$$out" | grep -qE "already initialized|AlreadyExists" && { echo "✓ etcd already bootstrapped"; break; }; \
	  i=$$((i+1)); \
	  [ $$i -ge 30 ] && { echo "✗ Timed out waiting for bootstrap"; exit 1; }; \
	  echo "  bootstrap attempt $$i/30, retrying in 10s ..."; sleep 10; \
	done

# Re-fetch kubeconfig (useful after MIG replaces the control plane or on first
# bootstrap).  The Kubernetes API can take 10+ min after etcd bootstrap.
kubeconfig:
	@CTRL_IP=$$(cd terraform && terraform output -raw control_plane_ip) && \
	echo "→ Waiting for Kubernetes API ..." && \
	i=0; while ! talosctl kubeconfig $(KUBECONFIG) \
	    --nodes $$CTRL_IP --endpoints $$CTRL_IP \
	    --talosconfig $(TALOS_DIR)/talosconfig \
	    --force >/dev/null 2>&1; do \
	  i=$$((i+1)); \
	  [ $$i -ge 90 ] && { echo "✗ Timed out waiting for Kubernetes API"; exit 1; }; \
	  echo "  attempt $$i/90, retrying in 10s ..."; sleep 10; \
	done && \
	echo "✓ $(KUBECONFIG) saved"

# After MIG auto-replaces preempted nodes, re-fetch kubeconfig once the
# control plane is back.  Workers re-join automatically (self-configured from
# instance metadata).
recover:
	@echo "→ MIG is replacing preempted instances automatically."
	@echo "  Workers self-configure from instance metadata on restart."
	@echo "  Waiting for control plane to come back ..."
	@$(MAKE) kubeconfig
	@echo "✓ Recovery complete — workers will rejoin within a few minutes"
	@echo "  kubectl get nodes --watch"

# Destroy all GCP resources and remove local cluster state
down:
	cd terraform && terraform destroy -auto-approve
	@rm -rf $(TALOS_DIR) $(KUBECONFIG)
	@echo "✓ Cluster destroyed"

status:
	@test -f $(KUBECONFIG) || { echo "✗ $(KUBECONFIG) not found — run 'make up' first"; exit 1; }
	KUBECONFIG=$(PWD)/$(KUBECONFIG) kubectl get nodes -o wide --request-timeout=10s
	@echo ""
	KUBECONFIG=$(PWD)/$(KUBECONFIG) kubectl get pods --all-namespaces --request-timeout=10s
	@echo ""
	@echo "── GCP resources ──────────────────────────────────────────────────"
	@gcloud compute instances list \
	  --project=$(PROJECT_ID) \
	  --filter="name~'^$(CLUSTER_NAME)'" \
	  --format="table(name:label=INSTANCE, zone.basename():label=ZONE, machineType.basename():label=TYPE, status:label=STATUS)" \
	  2>/dev/null || echo "  (could not list instances)"
	@echo ""
	@echo "── Billing (estimates) ────────────────────────────────────────────"
	@IP_STATUS=$$(gcloud compute addresses describe $(CLUSTER_NAME)-cp-ip \
	  --region=$(REGION) --project=$(PROJECT_ID) \
	  --format='value(status)' 2>/dev/null); \
	IP_ADDR=$$(gcloud compute addresses describe $(CLUSTER_NAME)-cp-ip \
	  --region=$(REGION) --project=$(PROJECT_ID) \
	  --format='value(address)' 2>/dev/null); \
	if [ "$$IP_STATUS" = "IN_USE" ]; then \
	  echo "  Static IP $$IP_ADDR: IN_USE (free while attached)"; IP_COST=0; \
	elif [ "$$IP_STATUS" = "RESERVED" ]; then \
	  echo "  Static IP $$IP_ADDR: RESERVED (billed while cluster is down)"; IP_COST=0.01; \
	else \
	  echo "  Static IP: not found"; IP_COST=0; \
	fi; \
	NODES=$$(gcloud compute instances list \
	  --project=$(PROJECT_ID) \
	  --filter="name~'^$(CLUSTER_NAME)' AND status=RUNNING" \
	  --format='value(name)' 2>/dev/null | wc -l | tr -d ' '); \
	case $(MACHINE_TYPE) in \
	  e2-micro)       SPOT_HR=0.0035 ;; \
	  e2-small)       SPOT_HR=0.0056 ;; \
	  e2-medium)      SPOT_HR=0.0100 ;; \
	  e2-standard-2)  SPOT_HR=0.0200 ;; \
	  e2-standard-4)  SPOT_HR=0.0401 ;; \
	  e2-standard-8)  SPOT_HR=0.0801 ;; \
	  n2-standard-2)  SPOT_HR=0.0244 ;; \
	  n2-standard-4)  SPOT_HR=0.0487 ;; \
	  n2d-standard-2) SPOT_HR=0.0196 ;; \
	  n2d-standard-4) SPOT_HR=0.0392 ;; \
	  t2d-standard-1) SPOT_HR=0.0099 ;; \
	  t2d-standard-2) SPOT_HR=0.0198 ;; \
	  *)              SPOT_HR=0.0100 ;; \
	esac; \
	awk -v nodes=$$NODES -v spot_hr=$$SPOT_HR \
	    -v disk=$(DISK_SIZE_GB) -v mtype=$(MACHINE_TYPE) \
	    -v ip_cost=$$IP_COST 'BEGIN { \
	  d      = sprintf("%c", 36); \
	  vm_hr  = nodes * spot_hr; \
	  vm_day = vm_hr  * 24; \
	  vm_mon = vm_day * 30; \
	  dk_hr  = nodes * disk * 0.04 / 30 / 24; \
	  dk_day = dk_hr  * 24; \
	  dk_mon = dk_day * 30; \
	  img_mon = 0.10; \
	  ip_mon  = ip_cost * 24 * 30; \
	  tot_hr  = vm_hr  + dk_hr  + ip_cost + img_mon/30/24; \
	  tot_day = vm_day + dk_day + ip_cost*24 + img_mon/30; \
	  tot_mon = vm_mon + dk_mon + ip_mon + img_mon; \
	  f = "  %-28s  %s%.3f/hr  %s%.2f/day  %s%.2f/month\n"; \
	  printf f, sprintf("VMs (%dx %s spot)", nodes, mtype), d, vm_hr,  d, vm_day,    d, vm_mon; \
	  printf f, sprintf("Disks (%dx %dGB PD)", nodes, disk), d, dk_hr,  d, dk_day,    d, dk_mon; \
	  printf "  %-28s  %10s  %9s  %s%.2f/month\n", "Image + GCS", "—", "—", d, img_mon; \
	  if (ip_cost > 0) printf f, "Static IP (idle)", d, ip_cost, d, ip_cost*24, d, ip_mon; \
	  printf f, "Total", d, tot_hr, d, tot_day, d, tot_mon; \
	  printf "  (spot prices are estimates; actual prices vary by region)\n"; \
	}'

# Destroy all GCP resources and remove the Talos image and GCS bucket created
# by `make image` — the only things that incur cost after `make down`.
stop_billing: down
	@test -n "$(PROJECT_ID)" || { echo "✗ project_id not found in terraform/terraform.tfvars"; exit 1; }
	@echo "→ Deleting Talos compute image ..."
	@gcloud compute images delete $(IMAGE_NAME) --project=$(PROJECT_ID) --quiet 2>/dev/null && \
	  echo "✓ Image $(IMAGE_NAME) deleted" || echo "  (image not found — skipping)"
	@echo "→ Deleting GCS bucket ..."
	@gsutil rm -r gs://$(PROJECT_ID)-talos-images/ 2>/dev/null && \
	  echo "✓ Bucket gs://$(PROJECT_ID)-talos-images/ deleted" || echo "  (bucket not found — skipping)"
	@echo "✓ All billing stopped"

history:
	@test -n "$(PROJECT_ID)" || { echo "✗ project_id not found in terraform/terraform.tfvars"; exit 1; }
	@echo "Preemption events for cluster '$(CLUSTER_NAME)' in zone $(ZONE):"
	@gcloud compute operations list \
	  --project=$(PROJECT_ID) \
	  --filter="operationType=compute.instances.preempted AND targetLink~'$(CLUSTER_NAME)'" \
	  --format="table(insertTime.date('%Y-%m-%d %H:%M:%S'):label=TIME, targetLink.basename():label=INSTANCE)" \
	  --sort-by=insertTime

clean:
	rm -rf terraform/.terraform terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
	rm -rf $(TALOS_DIR) $(KUBECONFIG)
	@echo "✓ Local state cleaned"

.DEFAULT_GOAL := help
