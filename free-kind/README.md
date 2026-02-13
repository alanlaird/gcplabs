# free-kind

Three-node Kubernetes cluster on GCP spot instances, provisioned with Terraform and configured with Ansible using kubeadm.

## Architecture

| Node | Role | Machine Type | Disk | Notes |
|------|------|-------------|------|-------|
| kind1 | Control plane | e2-standard-2 | 30GB pd-standard | SPOT, runs etcd + API server |
| kind2 | Worker | e2-standard-2 | 30GB pd-standard | SPOT |
| kind3 | Worker | e2-standard-2 | 30GB pd-standard | SPOT |

All instances run Debian 12 in `us-west1-b` on a shared VPC. Flannel CNI provides pod networking with `10.244.0.0/16`.

## Files

| File | Description |
|------|-------------|
| `main.tf` | Three e2-standard-2 spot instances, VPC, firewall rules (SSH, K8s API 6443, internal) |
| `variables.tf` | Project, region, zone, SSH user/key variables |
| `outputs.tf` | External and internal IPs for all instances |
| `playbook.yml` | Ansible playbook: SSH setup, Docker, containerd, kubeadm cluster bootstrap |
| `ansible.cfg` | Ansible defaults for inventory, user, and key |
| `deploy.sh` | Full deploy: terraform apply, generate inventory, wait for SSH, run ansible |
| `ssh-kind1.sh` | SSH to kind1 (control plane) |
| `ssh-kind2.sh` | SSH to kind2 (worker) |
| `ssh-kind3.sh` | SSH to kind3 (worker) |
| `costs.sh` | Estimated daily/monthly GCP costs |
| `id_gcp` / `id_gcp.pub` | SSH keypair for instance access |

## Deploy

```bash
./deploy.sh
```

This will:
1. Initialize and apply Terraform (creates 3 spot instances + VPC + firewall rules)
2. Generate an Ansible inventory from Terraform outputs
3. Wait for SSH on all instances
4. Run the Ansible playbook which:
   - Configures `/etc/hosts` and `~/.ssh/config` for mutual SSH between all nodes
   - Installs Docker CE and configures containerd for Kubernetes
   - Installs kubeadm, kubelet, and kubectl (v1.31)
   - Initializes the control plane on kind1 with Flannel CNI
   - Joins kind2 and kind3 as worker nodes
   - Distributes kubeconfig to all nodes

## SSH Access

From your local machine using helper scripts:
```bash
./ssh-kind1.sh              # interactive shell on kind1
./ssh-kind1.sh kubectl get nodes   # run a remote command
```

From any instance to another:
```bash
ssh kind1
ssh kind2
ssh kind3
```

## Cluster Health

Check node status:
```
$ ./ssh-kind1.sh kubectl get nodes
NAME    STATUS   ROLES           AGE     VERSION
kind1   Ready    control-plane   7h31m   v1.31.14
kind2   Ready    <none>          7h30m   v1.31.14
kind3   Ready    <none>          98s     v1.31.14
```

Check system pods:
```
$ ./ssh-kind1.sh kubectl get pods -A
NAMESPACE      NAME                            READY   STATUS    RESTARTS   AGE
kube-flannel   kube-flannel-ds-s7lqg           1/1     Running   0          98s
kube-flannel   kube-flannel-ds-tf2lk           1/1     Running   0          7h30m
kube-flannel   kube-flannel-ds-zl5vd           1/1     Running   0          7h30m
kube-system    coredns-7c65d6cfc9-b4qbb        1/1     Running   0          7h31m
kube-system    coredns-7c65d6cfc9-wgclm        1/1     Running   0          7h31m
kube-system    etcd-kind1                      1/1     Running   0          7h31m
kube-system    kube-apiserver-kind1            1/1     Running   0          7h31m
kube-system    kube-controller-manager-kind1   1/1     Running   0          7h31m
kube-system    kube-proxy-7hftw                1/1     Running   0          7h31m
kube-system    kube-proxy-ndh8m                1/1     Running   0          7h30m
kube-system    kube-proxy-sw778                1/1     Running   0          98s
kube-system    kube-scheduler-kind1            1/1     Running   0          7h31m
```

Run a test workload:
```
$ ./ssh-kind1.sh "kubectl run test1 --image=nginx --restart=Never && kubectl run test2 --image=nginx --restart=Never"
pod/test1 created
pod/test2 created

$ ./ssh-kind1.sh kubectl get pods -o wide
NAME    READY   STATUS    RESTARTS   AGE   IP           NODE    NOMINATED NODE   READINESS GATES
test1   1/1     Running   0          16s   10.244.1.3   kind2   <none>           <none>
test2   1/1     Running   0          16s   10.244.2.2   kind3   <none>           <none>
```

Pods are distributed across both worker nodes.

## Cost Estimate

```bash
./costs.sh
```

All three instances are SPOT (preemptible) e2-standard-2. Spot pricing is approximately 70% off on-demand. External IP charges apply ($0.004/hr each).

## Teardown

```bash
terraform destroy
```

## Notes

- SPOT instances may be preempted by GCP at any time. The cluster will need to be redeployed if that happens.
- The `--ignore-preflight-errors=Mem` flag is used for kubeadm on smaller instances. With e2-standard-2 (8GB RAM) this is no longer strictly needed but is kept for compatibility.
- The playbook is idempotent — running `./deploy.sh` again will skip already-completed steps.
