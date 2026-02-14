#!/bin/bash
# Initialize minimal GKE setup

set -e

echo "=========================================="
echo "Minimal GKE Cluster Setup Initialize"
echo "=========================================="

# Check prerequisites
echo ""
echo "✓ Checking prerequisites..."

command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud CLI not found. Install with: brew install google-cloud-sdk"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform not found. Install with: brew install terraform"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found. Install with: gcloud components install kubectl"; exit 1; }
command -v ansible >/dev/null 2>&1 || { echo "❌ Ansible not found. Install with: pip install ansible"; exit 1; }

echo "✓ All prerequisites found!"

# Get GCP project
echo ""
echo "Enter your GCP project ID (or press Enter to use current):"
read -r PROJECT_ID
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}

if [ -z "$PROJECT_ID" ]; then
    echo "❌ No GCP project ID provided or set"
    exit 1
fi

echo "✓ Using project: $PROJECT_ID"

# Set up Terraform
echo ""
echo "Setting up Terraform..."
cd terraform

if [ ! -f terraform.tfvars ]; then
    echo "Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    sed -i '' "s/your-gcp-project-id/$PROJECT_ID/" terraform.tfvars
    echo "✓ terraform.tfvars created"
else
    echo "✓ terraform.tfvars already exists"
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

echo ""
echo "=========================================="
echo "✓ Initialization Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Review and update terraform/terraform.tfvars if needed"
echo "2. Run: cd terraform && terraform plan"
echo "3. Run: terraform apply"
echo "4. Run: configure the kubeconfig"
echo "5. Run: ansible playbooks from the ansible directory"
echo ""
echo "For more details, see README.md"
