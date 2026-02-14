# Minimal Cost-Effective GKE Cluster with Terraform & Ansible

This project provides Infrastructure as Code (IaC) for creating an inexpensive Google Kubernetes Engine (GKE) cluster using Terraform and configuring it with Ansible.

## Features

✅ **Cost Optimizations:**
- Pre-emptible VMs (70% cost reduction)
- Small machine types (e2-medium)
- Auto-scaling (1-3 nodes)
- Minimal storage (30GB disk)
- Private cluster networking
- Resource quotas and limits

✅ **Security:**
- Shielded GKE nodes
- Network policies
- Workload Identity
- Private subnets
- Cloud Armor ready

✅ **Monitoring:**
- Google Cloud Logging
- Google Cloud Monitoring
- Resource quotas
- Pod Disruption Budgets

## Prerequisites

### Required Tools

- **Terraform** >= 1.0  
  ```bash
  brew install terraform  # macOS
  ```

- **Google Cloud SDK**  
  ```bash
  brew install google-cloud-sdk  # macOS
  ```

- **kubectl**  
  ```bash
  gcloud components install kubectl
  ```

- **Ansible** >= 2.10  
  ```bash
  pip install ansible google-auth
  ```

- **Kubernetes Python Client** (for Ansible)  
  ```bash
  pip install kubernetes
  ```

### GCP Setup

1. Create a GCP project:
   ```bash
   gcloud projects create min-gke-project --name="Minimal GKE"
   gcloud config set project min-gke-project
   ```

2. Enable required APIs:
   ```bash
   gcloud services enable container.googleapis.com
   gcloud services enable compute.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

3. Create a service account (optional but recommended):
   ```bash
   gcloud iam service-accounts create terraform-sa \
     --display-name="Terraform Service Account"
   
   gcloud projects add-iam-policy-binding min-gke-project \
     --member="serviceAccount:terraform-sa@min-gke-project.iam.gserviceaccount.com" \
     --role="roles/container.admin"
   
   gcloud projects add-iam-policy-binding min-gke-project \
     --member="serviceAccount:terraform-sa@min-gke-project.iam.gserviceaccount.com" \
     --role="roles/compute.admin"
   ```

## Deployment Steps

### Step 1: Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
project_id = "your-gcp-project-id"
region      = "us-central1"  # Change if needed
```

### Step 2: Deploy Infrastructure with Terraform

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

This will:
- Create a VPC network
- Create subnets with secondary ranges
- Provision a GKE cluster
- Create a node pool with autoscaling

**Time to complete:** ~10-15 minutes

### Step 3: Get Cluster Credentials

```bash
# Configure kubectl to access the cluster
gcloud container clusters get-credentials min-gke-cluster \
  --region=us-central1 \
  --project=your-project-id

# Verify cluster access
kubectl get nodes
```

### Step 4: Run Ansible Playbooks

```bash
cd ../ansible

# Set environment variables
export GCP_PROJECT_ID="your-project-id"

# Run cluster setup
ansible-playbook playbooks/setup_cluster.yml

# Configure cost optimization
ansible-playbook playbooks/cost_optimization.yml

# (Optional) Deploy sample application
ansible-playbook playbooks/deploy_sample_app.yml
```

## Project Structure

```
min-gke/
├── terraform/
│   ├── provider.tf           # GCP provider configuration
│   ├── main.tf              # GKE cluster and network resources
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values
│   └── terraform.tfvars.example  # Example values
├── ansible/
│   ├── ansible.cfg          # Ansible configuration
│   ├── inventory            # Ansible inventory
│   ├── playbooks/
│   │   ├── setup_cluster.yml           # Initial cluster setup
│   │   ├── deploy_sample_app.yml       # Deploy sample Nginx app
│   │   ├── cleanup_sample_app.yml      # Clean up sample app
│   │   └── cost_optimization.yml       # Configure cost controls
│   └── roles/               # Ansible roles (expandable)
└── README.md               # This file
```

## Cost Estimates

**Monthly costs (us-central1 region):**

| Component | Unit Cost | Quantity | Monthly |
|-----------|-----------|----------|---------|
| GKE Control Plane | $0.10 | 1 | $0.10 |
| e2-medium (preemptible) | ~$0.0263/hr | 24/7 | ~$19.00 |
| Persistent disk (30GB) | $1.60 | 1 | $1.60 |
| **Total (1 node)** | | | **~$20.70** |
| **Total (2 nodes)** | | | **~$40.30** |
| **Total (3 nodes)** | | | **~$59.90** |

*Prices vary by region. Use [GCP Pricing Calculator](https://cloud.google.com/products/calculator) for accurate estimates.*

## Common Operations

### View Cluster Status

```bash
# Get cluster info
kubectl cluster-info

# List nodes
kubectl get nodes -o wide

# Check resource usage
kubectl top nodes
kubectl top pods
```

### Scale Nodes Manually
```

## Accessing Your GKE Cluster with kubectl

After deploying with Terraform, configure your local kubectl to access the cluster:

```bash
gcloud container clusters get-credentials min-gke-cluster \
  --region=us-central1 \
  --project=your-project-id

# Test access
kubectl get nodes
```

## Measuring Cluster Health

Check the health and status of your cluster and workloads:

```bash
# Get cluster info (API endpoints, DNS, etc)


# List all nodes and their status
```bash

# List all pods in all namespaces
# Scale node pool to 2 nodes

# Check if all system pods are running
gcloud container clusters resize min-gke-cluster \

# View events for troubleshooting
  --num-nodes 2 \

# Check resource usage (requires metrics-server)
  --region us-central1
```

# Describe a node for detailed health


# Check component statuses (deprecated in newer k8s, but still useful)
### Update Kubernetes Version
```

## Creating a Simple Service (Nginx Example)

You can quickly deploy and expose a simple Nginx web server:

```bash
# 1. Create a deployment
kubectl create deployment nginx --image=nginx

# 2. Expose the deployment as a LoadBalancer service
kubectl expose deployment nginx --type=LoadBalancer --port=80

# 3. Get the external IP (may take a minute to provision)
kubectl get service nginx

# 4. Test access (replace <EXTERNAL-IP> with the value from above)
curl http://<EXTERNAL-IP>

# 5. Clean up
kubectl delete service nginx
kubectl delete deployment nginx

Edit `kubernetes_version` in `terraform/terraform.tfvars` and run:

```bash
terraform apply
```

### Access Cluster via kubectl

```bash
# Already configured from setup, but can refresh with:
gcloud container clusters get-credentials min-gke-cluster \
  --region us-central1 \
  --project your-project-id
```

### Deploy Applications

```bash
# Deploy sample Nginx app
ansible-playbook ansible/playbooks/deploy_sample_app.yml

# Or use kubectl directly
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80
```

### Monitor Costs

```bash
# View cluster costs in Cloud Console
gcloud billing projects list

# or use kubecost (optional)
kubectl krew install cost-analyzer
kubectl cost-analyzer
```

## Cleanup

### Destroy All Resources

```bash
# Remove Kubernetes resources
ansible-playbook ansible/playbooks/cleanup_sample_app.yml

# Destroy infrastructure
cd terraform
terraform destroy
```

**⚠️ Warning:** This will delete the cluster and all data. Ensure you have backups if needed.

## Troubleshooting

### Terraform Issues

```bash
# Check terraform state
terraform state list
terraform state show google_container_cluster.primary

# Debug with verbose output
terraform apply -refresh=true
```

### Cluster Access Issues

```bash
# Verify credentials are configured
gcloud config list

# Re-authenticate if needed
gcloud auth login
gcloud auth application-default login

# Check cluster is accessible
gcloud container clusters describe min-gke-cluster --region=us-central1
```

### Ansible Issues

```bash
# Test Kubernetes connectivity
ansible-playbook playbooks/setup_cluster.yml -v

# Verify kubectl can access cluster
kubectl get pods --all-namespaces

# Check Ansible requirements
python3 -m pip show kubernetes
```

### Preemptible Node Issues

If preemptible nodes cause instability:
1. Edit `terraform/terraform.tfvars`
2. Set `enable_preemptible_nodes = false`
3. Run `terraform apply`

*Note: This will increase costs.*

## Advanced Customization

### Add Custom Node Pools

In `terraform/main.tf`, add additional `google_container_node_pool` resources.

### Enable Advanced Networking

Update `ip_allocation_policy` in `terraform/main.tf` to use different CIDR ranges.

### Add Ingress Controller

```bash
# Install Nginx Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### Enable VPA (Vertical Pod Autoscaling)

Follow [GKE VPA documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/verticalpodautoscaler).

## Cost Optimization Tips

1. **Use preemptible VMs** (enabled by default - 70% savings)
2. **Right-size instances** - e2-medium is often sufficient
3. **Implement resource requests/limits** - Prevents overprovisioning
4. **Use auto-scaling** - Let GKE scale down unused nodes
5. **Clean up Load Balancers** - GCP charges for external IPs
6. **Use image pull-through cache** - Reduces egress costs
7. **Implement pod priority classes** - Manage critical vs. batch workloads

## Security Best Practices

✅ Network policies enabled  
✅ Shielded nodes enabled  
✅ Workload Identity configured  
✅ Resource quotas enforced  
✅ Private cluster ready  

For production, consider:
- Enabling Workload Identity for all services
- Using Google Cloud Armor
- Implementing PSP/Pod Security Standards
- Regular security audits
- Backup and disaster recovery

## Monitoring and Logging

Monitoring is enabled by default with Google Cloud Logging and Monitoring:

```bash
# View logs in Cloud Console
gcloud logging read "resource.type=k8s_cluster" --limit 10

# View metrics
gcloud monitoring time-series list --filter='metric.type=kubernetes.io/*'
```

## Contributing

To improve this setup:
1. Test on your GCP project
2. Document any customizations
3. Share improvements

## License

This project is provided as-is for educational and testing purposes.

## Support

For issues:
1. Check [GKE documentation](https://cloud.google.com/kubernetes-engine/docs)
2. Review [Terraform GCP provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
3. Consult [Ansible documentation](https://docs.ansible.com/)

## Additional Resources

- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [GKE Pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [Ansible Kubernetes Module](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/index.html)
- [Google Cloud Free Tier](https://cloud.google.com/free)

---

**Created:** February 2026  
**Last Updated:** February 2026
