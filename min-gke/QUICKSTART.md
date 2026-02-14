# Quick Start Guide

## 5-Minute Quick Start

### Prerequisites
```bash
brew install terraform google-cloud-sdk
gcloud components install kubectl
pip install ansible google-auth kubernetes
```

### Deploy
```bash
# 1. Set project
export GCP_PROJECT_ID="your-project-id"
gcloud config set project $GCP_PROJECT_ID

# 2. Enable APIs
gcloud services enable container.googleapis.com compute.googleapis.com

# 3. Update variables
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set project_id

# 4. Deploy cluster
terraform init
terraform apply

# 5. Get credentials
gcloud container clusters get-credentials min-gke-cluster --region=us-central1 --project=$GCP_PROJECT_ID

# 6. Configure cluster
cd ../ansible
export GCP_PROJECT_ID=$GCP_PROJECT_ID
ansible-playbook playbooks/setup_cluster.yml
ansible-playbook playbooks/cost_optimization.yml

# 7. Test
kubectl get nodes
```

## Using Make Commands

```bash
make help              # See all commands
make init             # Initialize Terraform
make plan             # Plan changes
make apply            # Create cluster
make kubeconfig       # Configure kubectl
make ansible-setup    # Set up cluster with Ansible
make ansible-optimize # Configure cost controls
make status           # Check cluster status
make destroy          # Delete cluster
```

## Common Tasks

### Deploy an app
```bash
kubectl create deployment myapp --image=myimage
kubectl expose deployment myapp --type=LoadBalancer --port=80
```

### Scale cluster
```bash
# Manual scale
gcloud container clusters resize min-gke-cluster --num-nodes 2 --region us-central1

# Or edit terraform.tfvars and run: terraform apply
```

### View costs
Check GCP Console > Billing > Costs

### Delete everything
```bash
make destroy
# Or manually: cd terraform && terraform destroy
```

## Troubleshooting

**Can't access cluster?**
```bash
gcloud container clusters get-credentials min-gke-cluster --region=us-central1 --project=$GCP_PROJECT_ID
```

**Need to change region?**
Edit `terraform.tfvars`:
```hcl
region = "europe-west1"
```
Then run `terraform apply`

**Preemptible nodes too unstable?**
Edit `terraform.tfvars`:
```hcl
enable_preemptible_nodes = false
```
Then run `terraform apply`

**Want smaller/larger nodes?**
Edit `terraform.tfvars`:
```hcl
machine_type = "e2-small"  # or e2-standard-2, etc
```
Then run `terraform apply`

## Clean up Terraform files
```bash
make clean
# Or: cd terraform && rm -rf .terraform .terraform.lock.hcl *.tfstate*
```

## More Information
See README.md for detailed documentation.
