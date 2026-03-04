# spot-kind-submariner

Three GCP SPOT instances each running a kind (Kubernetes-in-Docker) cluster,
linked via [Submariner](https://submariner.io/) for cross-cluster pod networking
and service discovery. Provisioned with Terraform and configured with Ansible.

## Architecture

Each GCP VM runs Docker with a kind cluster named after the VM (`kind1`, `kind2`, `kind3`).
Pod CIDRs are non-overlapping so Submariner can route between them.

| Node | Machine | Pod CIDR | Service CIDR | Submariner role |
|------|---------|----------|--------------|-----------------|
| kind1 | e2-standard-2 SPOT | 10.244.0.0/16 | 10.96.0.0/16 | broker + gateway |
| kind2 | e2-standard-2 SPOT | 10.245.0.0/16 | 10.97.0.0/16 | gateway |
| kind3 | e2-standard-2 SPOT | 10.246.0.0/16 | 10.98.0.0/16 | gateway |

VXLAN tunnels (UDP 4500/4800) run between gateway pods. Each VM's Docker worker
container exposes ports 4490/4500/4800 via kind `extraPortMappings`.

## Files

| File | Description |
|------|-------------|
| `main.tf` | GCP instances (3), VPC, firewall rules including UDP 4490/4500/4800 for Submariner |
| `variables.tf` | Project, region, zone, SSH user/key |
| `outputs.tf` | `external_ips` and `internal_ips` arrays |
| `playbook.yml` | Docker + kind + kubectl install, per-node cluster config, gateway labeling |
| `ansible.cfg` | Ansible defaults |
| `Makefile` | All workflow targets (see below) |
| `submariner.md` | Submariner demo commands and troubleshooting |

## Quick Start

```bash
make create
```

Downloads `kubeconfig.yaml` locally at the end with one context per cluster.

## Makefile Targets

```
make help           # show all targets

make create         # 3 VMs + kind clusters + Submariner
make submariner     # (re)deploy Submariner broker and join clusters

make kubeconfig     # fetch/merge kubeconfigs -> kubeconfig.yaml
make demo           # deploy nginx to each cluster and show pods

make ssh1 / ssh2 / ssh3   # SSH to each VM
make destroy        # terraform destroy
make clean          # destroy + remove generated files
make reset-clusters # rebuild clusters with correct Docker subnets
```

## Local kubectl Usage

After `make create`:

```bash
export KUBECONFIG=$PWD/kubeconfig.yaml

kubectl config get-contexts
kubectl --context kind-kind1 get nodes
kubectl --context kind-kind2 get pods -A
kubectl --context kind-kind3 get nodes
```

## Cross-Cluster Networking

See [`submariner.md`](submariner.md) for full demo including:
- Cross-cluster pod ping
- Service export/import via `ServiceExport` CRD
- `subctl verify` connectivity suite
- Troubleshooting tips

Quick check after `make create`:
```bash
subctl show connections --kubeconfig kubeconfig-kind1.yaml
```

## Notes

- **SPOT instances**: May be preempted at any time. Re-run `make create` to redeploy.
  The playbook is idempotent — existing clusters are detected and skipped.
- **Docker subnets**: Each VM gets a unique Docker subnet (172.21-23.0.0/16) to avoid
  Submariner VTEP IP collisions. See `submariner.md` for details.
- **kind vs kubeadm**: Each kind cluster runs as Docker containers on the VM. Lighter
  than kubeadm and faster to provision (~3 min vs ~10 min).
- **Cluster access**: API server certs include both internal and external GCP IPs, so
  `kubectl` works from local machine (external IP) and from other VMs (internal IP).

## Teardown

```bash
make clean   # terraform destroy + remove local kubeconfig files
```
