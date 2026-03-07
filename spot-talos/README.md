# spot-talos

Talos Linux Kubernetes cluster on GCP spot instances, provisioned with Terraform and configured via `talosctl`. No SSH, no Ansible — Talos is managed entirely through its API.

## Architecture

- 1 control plane node (SPOT, MIG-managed)
- 2 worker nodes (SPOT, MIG-managed, configurable)
- Talos Linux OS (immutable, API-managed)
- Flannel CNI (Talos default)
- GCP firewall: Talos API (50000), Kubernetes API (6443), inter-node all traffic
- **MIG auto-healing**: preempted instances are replaced automatically; nodes self-configure from machine config embedded in instance metadata

## Prerequisites

```
brew install terraform siderolabs/tap/talosctl google-cloud-sdk jq
```

Authenticate with GCP:
```
gcloud auth application-default login
```

## Quick Start

```bash
# 1. Configure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars — set project_id

# 2. Import Talos GCP image (one-time per project/version)
make image

# 3. Create cluster
make up
```

`make up` uses a two-phase terraform apply:

1. **Phase 1** — creates infrastructure: network, reserved static IP for the control plane, MIGs (nodes boot into Talos maintenance mode)
2. **genconfig** — generates Talos machine configs targeting the static IP (stable endpoint across restarts)
3. **Phase 2** — embeds machine configs as `user-data` in instance templates; MIG rolls out replacement instances that self-configure on boot
4. Wait for Talos API, bootstrap etcd, fetch `kubeconfig.yaml`

## Usage

```bash
make up         # Create cluster
make down       # Destroy all resources
make recover    # Re-fetch kubeconfig after MIG auto-replaces nodes
make kubeconfig # Re-fetch kubeconfig from control plane
make status       # kubectl get nodes + pods
make history      # Show spot preemption history
make stop_billing # Destroy everything including Talos image and GCS bucket
make clean        # Remove local state files
make prereqs      # Check tool dependencies
```

```bash
# Use the cluster
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get nodes
```

## Spot preemption recovery

MIG auto-healing detects preempted instances (via TCP health check on port 50000) and replaces them automatically. Replacement instances self-configure from Talos machine config embedded in the instance template metadata — no manual intervention needed.

After the control plane restarts:

```bash
make recover   # waits for the K8s API and re-fetches kubeconfig
```

Workers rejoin the cluster on their own once they finish booting.

## Talos version

The default is `v1.12.4`. To use a different version, update `TALOS_VERSION` in the Makefile and `talos_version` in `terraform/terraform.tfvars`, then re-run `make image` and `make up`.

Check latest releases: https://github.com/siderolabs/talos/releases

## Talos management

The `talos/` directory (gitignored) contains the machine configs and `talosconfig` for this cluster:

```bash
# Check cluster health
talosctl health \
  --nodes $(cd terraform && terraform output -raw control_plane_ip) \
  --endpoints $(cd terraform && terraform output -raw control_plane_ip) \
  --talosconfig talos/talosconfig

# Access Talos dashboard (TUI)
talosctl dashboard \
  --nodes $(cd terraform && terraform output -raw control_plane_ip) \
  --endpoints $(cd terraform && terraform output -raw control_plane_ip) \
  --talosconfig talos/talosconfig
```

## Notes

- **No SSH**: Talos does not run SSH. All management is via `talosctl` on port 50000.
- **Static control plane IP**: a GCP reserved address is used so the Talos/K8s endpoint embedded in machine configs never changes across MIG restarts.
- **Secrets**: `talos/` and `kubeconfig.yaml` are gitignored — they contain cluster credentials. Back them up if needed.
- **GCS bucket**: `make image` creates a `${PROJECT_ID}-talos-images` GCS bucket to stage the disk image for import. It can be deleted after the compute image is created.
- **Worker IPs**: managed by MIG and change on restart. Use `terraform output worker_ips_cmd` to get the gcloud command to list current IPs.
