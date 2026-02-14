.PHONY: help init plan apply destroy clean kubeconfig prereqs ansible-setup

help:
	@echo "Minimal GKE Cluster Management"
	@echo ""
	@echo "Available targets:"
	@echo "  make prereqs          - Check and install prerequisites"
	@echo "  make init            - Initialize Terraform"
	@echo "  make plan            - Plan Terraform changes"
	@echo "  make apply           - Apply Terraform configuration"
	@echo "  make destroy         - Destroy all resources"
	@echo "  make kubeconfig      - Configure kubectl access"
	@echo "  make ansible-setup   - Run Ansible cluster setup"
	@echo "  make ansible-optimize - Configure cost optimization"
	@echo "  make ansible-deploy  - Deploy sample app"
	@echo "  make ansible-cleanup - Clean up sample app"
	@echo "  make clean           - Clean local Terraform files"
	@echo "  make status          - Show cluster status"
	@echo "  make cost-estimate   - Estimate monthly costs"
	@echo ""

prereqs:
	@echo "Checking prerequisites..."
	@command -v gcloud >/dev/null 2>&1 || { echo "Install Google Cloud SDK: brew install google-cloud-sdk"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "Install Terraform: brew install terraform"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Install kubectl: gcloud components install kubectl"; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo "Install Ansible: pip install ansible"; exit 1; }
	@echo "✓ All prerequisites found"

init: prereqs
	@cd terraform && terraform init

plan:
	@cd terraform && terraform plan

apply:
	@cd terraform && terraform apply

destroy:
	@cd terraform && terraform destroy

kubeconfig:
	@PROJECT_ID=$$(cd terraform && terraform output -raw project_id 2>/dev/null || echo ""); \
	CLUSTER=$$(cd terraform && terraform output -raw kubernetes_cluster_name 2>/dev/null || echo "min-gke-cluster"); \
	REGION=$$(cd terraform && terraform output -raw region 2>/dev/null || echo "us-central1"); \
	if [ -n "$$PROJECT_ID" ]; then \
		gcloud container clusters get-credentials $$CLUSTER --region=$$REGION --project=$$PROJECT_ID; \
	else \
		echo "Terraform outputs not available. Configure manually or run 'terraform apply' first"; \
	fi

ansible-setup: kubeconfig
	@cd ansible && ansible-playbook playbooks/setup_cluster.yml

ansible-optimize: kubeconfig
	@cd ansible && ansible-playbook playbooks/cost_optimization.yml

ansible-deploy: kubeconfig
	@cd ansible && ansible-playbook playbooks/deploy_sample_app.yml

ansible-cleanup: kubeconfig
	@cd ansible && ansible-playbook playbooks/cleanup_sample_app.yml

status:
	@echo "Cluster Status:"
	@kubectl get nodes -o wide
	@echo ""
	@echo "Pods:"
	@kubectl get pods --all-namespaces

cost-estimate:
	@echo ""
	@echo "Estimated Monthly Costs (us-central1):"
	@echo "=========================================="
	@echo "1 node (e2-medium, preemptible): ~\$$20.70"
	@echo "2 nodes (e2-medium, preemptible): ~\$$40.30"
	@echo "3 nodes (e2-medium, preemptible): ~\$$59.90"
	@echo ""
	@echo "Note: Costs vary by region. Use GCP Pricing Calculator for accurate quotes."
	@echo "=========================================="
	@echo ""

clean:
	@cd terraform && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

.DEFAULT_GOAL := help
