# spot-k3s

Three-node k3s cluster on GCP **spot instances** — one master, two workers.
Infrastructure via Terraform, configuration via Ansible.

## Prerequisites

```bash
brew install terraform google-cloud-sdk
pip install ansible
gcloud auth application-default login
```

## Quick start

```bash
# 1. Configure your GCP project
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars   # set project_id

# 2. Create the cluster (~5 min)
make up

# 3. Use kubectl
kubectl get nodes
```

## Makefile targets

| Target | Description |
|--------|-------------|
| `make up` | Generate SSH keys → Terraform apply → Ansible configure k3s |
| `make down` | Destroy all GCP resources |
| `make kubeconfig` | Re-fetch kubeconfig from master |
| `make status` | `kubectl get nodes` + all pods |
| `make ssh` | SSH to master node |
| `make prereqs` | Verify required tools and config |
| `make clean` | Remove local Terraform state and generated files |

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  GCP VPC (10.0.0.0/24)  us-central1-a               │
│                                                      │
│  ┌─────────────────┐    ┌──────────┐  ┌──────────┐  │
│  │  spot-k3s-master│    │ worker-0 │  │ worker-1 │  │
│  │  k3s server     │    │ k3s agent│  │ k3s agent│  │
│  │  e2-medium/SPOT │    │ e2-medium│  │ e2-medium│  │
│  └────────┬────────┘    └────┬─────┘  └────┬─────┘  │
│           └─────────────────┴──────────────┘         │
└──────────────────────────────────────────────────────┘
```

## Spot instance behaviour

GCP Spot VMs can be preempted with 30 seconds notice. k3s handles node failures gracefully — pods are rescheduled automatically when nodes rejoin. For production workloads consider mixing spot + on-demand nodes.

## Files

```
spot-k3s/
├── Makefile
├── terraform/
│   ├── main.tf           # VPC, firewall, compute instances, inventory generation
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── inventory.tpl     # Ansible inventory template
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   └── playbook.yml      # k3s server → agents → kubeconfig
└── ssh/                  # generated, gitignored
    ├── k3s_key
    └── k3s_key.pub
```

## Cost estimate (us-central1, spot pricing ~80% discount)

| Resource | On-demand | Spot |
|----------|-----------|------|
| 3× e2-medium | ~$73/mo | ~$15/mo |
