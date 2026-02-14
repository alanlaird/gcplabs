# Project Summary

## What's Included

A complete, production-ready setup for deploying an inexpensive GKE cluster with cost optimization and security best practices built-in.

### Directory Structure

```
min-gke/
├── terraform/                          # Infrastructure as Code
│   ├── provider.tf                    # GCP provider setup
│   ├── main.tf                        # Network & cluster resources
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output values
│   └── terraform.tfvars.example       # Example configuration
│
├── ansible/                            # Configuration management
│   ├── ansible.cfg                    # Ansible configuration
│   ├── inventory                      # Inventory file
│   ├── playbooks/
│   │   ├── setup_cluster.yml          # Initial cluster setup
│   │   ├── deploy_sample_app.yml      # Deploy sample validation app
│   │   ├── cleanup_sample_app.yml     # Clean up sample app
│   │   └── cost_optimization.yml      # Configure cost controls
│   └── roles/                         # Room for custom roles
│
├── README.md                           # Comprehensive documentation
├── QUICKSTART.md                       # 5-minute quick start guide
├── Makefile                            # Convenient make commands
├── init.sh                             # Setup script
├── requirements.txt                    # Python dependencies
├── .gitignore                          # Git ignore rules
└── MANIFEST.md                         # This file

## Quick Start

### 1. Prerequisites
```bash
brew install terraform google-cloud-sdk
gcloud components install kubectl
pip install -r requirements.txt
```

### 2. Configure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID
```

### 3. Deploy
```bash
terraform init
terraform apply
```

### 4. Configure kubectl
```bash
gcloud container clusters get-credentials min-gke-cluster \
  --region=us-central1 \
  --project=YOUR_PROJECT_ID
```

### 5. Setup with Ansible
```bash
cd ../ansible
ansible-playbook playbooks/setup_cluster.yml
ansible-playbook playbooks/cost_optimization.yml
```

### 6. Verify
```bash
kubectl get nodes
```

## Features

### Cost Optimization
- **Preemptible VMs** (~70% cost savings)
- **Minimal machine types** (e2-medium)
- **Auto-scaling** (1-3 nodes)
- **Resource quotas** (prevent over-provisioning)
- **Right-sized storage** (30GB per node)
- **Estimated cost: ~$20.70/month** for 1 node

### Security
- **Shielded GKE nodes** with secure boot
- **Network policies** for pod-to-pod communication control
- **Workload Identity** for secure service-to-service auth
- **Private cluster networking** with VPC
- **Cloud Armor ready** for DDoS protection
- **Resource limits** to prevent resource exhaustion

### Monitoring & Observability
- **Google Cloud Logging** (GKE system logs)
- **Google Cloud Monitoring** (cluster & pod metrics)
- **Resource quotas** (track consumption)
- **Pod Disruption Budgets** (ensure availability)
- **LimitRanges** for container resource constraints

### Scalability
- **Horizontal Pod Autoscaling** (HPA)
- **Cluster autoscaling** (1-3 nodes)
- **Preemptible node support** for batch workloads
- **Secondary IP ranges** for future expansion

## Key Files Explained

### Terraform Files

**provider.tf**
- Configures Google Cloud provider
- Sets up authentication with GCP

**main.tf**
- Creates VPC network with secondary ranges for pods/services
- Provisions GKE cluster with:
  - Auto-scaling node groups
  - Network policies enabled
  - Workload Identity for pod IAM
  - Cloud Logging & Monitoring
- Configures node pool with cost optimizations

**variables.tf**
- Declares all input variables with defaults
- Allows customization without file editing

**outputs.tf**
- Exports cluster info: endpoint, kubeconfig command
- Used by Ansible for dynamic inventory

### Ansible Files

**setup_cluster.yml**
- Gets cluster credentials
- Validates cluster is ready
- Sets up monitoring namespace
- Creates resource quotas
- Applies network policies

**cost_optimization.yml**
- Creates Pod Disruption Budgets
- Sets up LimitRanges for containers
- Configures resource constraints

**deploy_sample_app.yml**
- Deploys Nginx sample application
- Creates LoadBalancer service
- Useful for cluster validation

**cleanup_sample_app.yml**
- Removes sample application
- Useful when testing is complete

## Making Changes

### Change Region
Edit `terraform/terraform.tfvars`:
```hcl
region = "europe-west1"
```
Then run `terraform apply`

### Disable Preemptible Nodes
Edit `terraform/terraform.tfvars`:
```hcl
enable_preemptible_nodes = false
```
Then run `terraform apply`

### Scale Cluster Size
Edit `terraform/terraform.tfvars`:
```hcl
min_node_count = 2
max_node_count = 5
```
Then run `terraform apply`

### Change Machine Type
Edit `terraform/terraform.tfvars`:
```hcl
machine_type = "e2-standard-2"  # Larger instance
```
Then run `terraform apply`

## Cost Estimation

**Monthly costs (in us-central1):**

| Nodes | Monthly Cost | Notes |
|-------|-------------|-------|
| 1 | ~$20.70 | Minimum viable |
| 2 | ~$40.30 | Recommended for HA |
| 3 | ~$59.90 | Production with buffer |

Preemptible nodes save ~70% on compute. 
Control plane (GKE) costs ~$0.10/month.
Data transfer and load balancers add extra costs.

## Cleanup

```bash
# Option 1: Use Terraform
cd terraform
terraform destroy

# Option 2: Use Make
make destroy
```

**Warning:** This will also delete any workloads running on the cluster.

## Support & Resources

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [Ansible Kubernetes Module](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)
- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)

## License

This project is provided as-is for educational and testing purposes.
See LICENSE file if present.

---

**Created:** February 2026  
**Last Modified:** February 2026
