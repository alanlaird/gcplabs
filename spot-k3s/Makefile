.PHONY: help prereqs keys init up down kubeconfig status clean

SSH_KEY    := ssh/k3s_key
SSH_PUB    := ssh/k3s_key.pub
INVENTORY  := ansible/inventory.ini
KUBECONFIG := kubeconfig.yaml

help:
	@echo "spot-k3s — Three-node k3s cluster on GCP spot instances"
	@echo ""
	@echo "  make up         Create cluster (terraform + ansible)"
	@echo "  make down       Destroy all GCP resources"
	@echo "  make kubeconfig Re-fetch kubeconfig from master"
	@echo "  make status     Show node and pod status"
	@echo "  make ssh        SSH to master node"
	@echo "  make prereqs    Check required tools"
	@echo "  make clean      Remove local state files"
	@echo ""
	@echo "First-time setup:"
	@echo "  1. cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
	@echo "  2. Edit terraform/terraform.tfvars with your GCP project ID"
	@echo "  3. make up"

prereqs:
	@command -v terraform      >/dev/null 2>&1 || { echo "✗ terraform not found:  brew install terraform"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "✗ ansible not found:    pip install ansible"; exit 1; }
	@command -v gcloud         >/dev/null 2>&1 || { echo "✗ gcloud not found:     brew install google-cloud-sdk"; exit 1; }
	@test -f terraform/terraform.tfvars || { echo "✗ terraform/terraform.tfvars not found — copy from terraform.tfvars.example"; exit 1; }
	@echo "✓ All prerequisites satisfied"

# Generate SSH keypair (only if it doesn't exist)
$(SSH_KEY):
	mkdir -p ssh
	ssh-keygen -t ed25519 -f $(SSH_KEY) -N "" -C "k3s-cluster"
	chmod 600 $(SSH_KEY)
	@echo "✓ SSH keypair created at $(SSH_KEY)"

keys: $(SSH_KEY)

init: keys
	cd terraform && terraform init

# Create cluster: provision infra then configure k3s
up: init
	cd terraform && terraform apply -auto-approve
	ansible-playbook -i $(INVENTORY) ansible/playbook.yml
	@echo ""
	@echo "✓ Cluster is up — KUBECONFIG=$(PWD)/$(KUBECONFIG)"
	@echo "  kubectl get nodes"

# Destroy all GCP resources
down:
	cd terraform && terraform destroy -auto-approve
	@rm -f $(INVENTORY) $(KUBECONFIG)
	@echo "✓ Cluster destroyed"

# Re-fetch kubeconfig (useful after node replacement)
kubeconfig:
	@test -f $(INVENTORY) || { echo "✗ $(INVENTORY) not found — run 'make up' first"; exit 1; }
	ansible-playbook -i $(INVENTORY) ansible/playbook.yml --tags kubeconfig
	@echo "✓ $(KUBECONFIG) updated"

status:
	kubectl get nodes -o wide
	@echo ""
	kubectl get pods --all-namespaces

ssh:
	@MASTER_IP=$$(cd terraform && terraform output -raw master_public_ip 2>/dev/null) && \
	SSH_USER=$$(cd terraform && terraform output -raw ssh_user 2>/dev/null) && \
	ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no $${SSH_USER}@$${MASTER_IP}

clean:
	rm -rf terraform/.terraform terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
	rm -f $(INVENTORY) $(KUBECONFIG)
	@echo "✓ Local state cleaned"

.DEFAULT_GOAL := help
