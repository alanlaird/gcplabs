# spot-kind

A single GCP SPOT instance running a kind (Kubernetes-in-Docker) cluster,
provisioned with Terraform and configured with Ansible.

## Architecture

One e2-standard-2 SPOT VM running Docker with a kind cluster (`kind1`):
1 control-plane + 1 worker node.

## Files

| File | Description |
|------|-------------|
| `main.tf` | GCP instance, VPC, firewall rules (SSH + k8s API) |
| `variables.tf` | Project, region, zone, SSH user/key |
| `outputs.tf` | `external_ip` and `internal_ip` |
| `playbook.yml` | Docker + kind + kubectl install, cluster creation |
| `ansible.cfg` | Ansible defaults |
| `Makefile` | All workflow targets (see below) |

## Quick Start

```bash
make create
```

Downloads `kubeconfig.yaml` locally at the end.

## Makefile Targets

```
make help       # show all targets

make create     # deploy VM + kind cluster
make kubeconfig # fetch kubeconfig -> kubeconfig.yaml
make demo       # show nodes and deploy a test pod

make ssh        # SSH to the VM
make destroy    # terraform destroy
make clean      # destroy + remove generated files
```

## Local kubectl Usage

After `make create`:

```bash
export KUBECONFIG=$PWD/kubeconfig.yaml

kubectl get nodes
kubectl get pods -A
kubectl run nginx --image=nginx --restart=Never
```

## Notes

- **SPOT instance**: May be preempted at any time. Re-run `make create` to redeploy.
  The playbook is idempotent — existing clusters are detected and skipped.
- **kind vs kubeadm**: The cluster runs as Docker containers on the VM. Lighter
  than kubeadm and faster to provision (~3 min vs ~10 min).
- **Cluster access**: API server certs include both internal and external GCP IPs, so
  `kubectl` works from local machine (external IP) and from inside the VPC (internal IP).

## Teardown

```bash
make clean   # terraform destroy + remove local kubeconfig
```

## Multi-cluster with Submariner

See [`../spot-kind-submariner`](../spot-kind-submariner) for a 3-VM setup with
Submariner cross-cluster networking.

