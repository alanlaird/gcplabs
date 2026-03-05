# gcplabs

GCP infrastructure experiments using Terraform and Ansible.

## Projects

| Directory | Description |
|-----------|-------------|
| [`spot-kind`](spot-kind/) | Single SPOT VM running a 2-node kind (Kubernetes-in-Docker) cluster. Fast to provision (~3 min), cheap to run. |
| [`spot-kind-submariner`](spot-kind-submariner/) | Three SPOT VMs each running a kind cluster, linked via [Submariner](https://submariner.io/) for cross-cluster pod networking and service discovery. |
| [`min-gke`](min-gke/) | Minimal cost GKE cluster with preemptible nodes, autoscaling, and Ansible-driven configuration. |

## Requirements

- **Terraform** >= 1.0
  ```bash
  brew install terraform
  ```

- **Google Cloud SDK**
  ```bash
  brew install google-cloud-sdk
  gcloud auth application-default login
  ```

- **Ansible** >= 2.10
  ```bash
  pip install ansible
  ```

- **kubectl**
  ```bash
  brew install kubectl
  ```

- **subctl** (spot-kind-submariner only)
  ```bash
  brew install submariner-io/submariner/subctl
  ```

- **direnv** (optional, for automatic KUBECONFIG switching)
  ```bash
  brew install direnv
  direnv allow   # run in each project dir after cloning
  ```

## GCP Setup

Each project uses a GCP project ID set in `variables.tf`. Authenticate before running:

```bash
gcloud auth application-default login
gcloud config set project <your-project-id>
```

Enable required APIs:

```bash
gcloud services enable compute.googleapis.com container.googleapis.com
```

## SSH Keys

Each project generates its own SSH key pair via `make keys`. Keys are excluded from git (`.gitignore`).

## Quick Start

```bash
cd spot-kind
make create       # provision VM + kind cluster (~3 min)
kubectl get nodes # uses kubeconfig.yaml in the directory
make destroy      # tear down
```
