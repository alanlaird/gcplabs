# free-kind

GCP free tier Kubernetes-ready instances provisioned with Terraform and configured with Ansible.

## Instances

| Name | Type | Machine | Notes |
|------|------|---------|-------|
| kind | Standard | e2-micro | Free tier eligible |
| kindspot | Spot | e2-micro | Preemptible/SPOT, free tier eligible |

Both instances run Debian 12 with 30GB standard persistent disks in `us-west1-b`.

## Files

| File | Description |
|------|-------------|
| `main.tf` | Two e2-micro instances on a shared VPC with SSH and internal firewall rules |
| `variables.tf` | Project, region, zone, SSH user/key variables |
| `outputs.tf` | External and internal IPs for both instances |
| `playbook.yml` | Ansible playbook: deploys SSH keys, /etc/hosts, and ~/.ssh/config |
| `ansible.cfg` | Ansible defaults for inventory, user, and key |
| `deploy.sh` | Wrapper script: terraform apply, generate inventory, wait for SSH, run ansible |
| `id_gcp` / `id_gcp.pub` | SSH keypair used for instance access |

## Deploy

```bash
./deploy.sh
```

This will:
1. Initialize and apply the Terraform configuration
2. Generate an Ansible inventory from Terraform outputs
3. Wait for SSH to become available on both instances
4. Run the Ansible playbook to configure:
   - `/etc/hosts` with internal IPs for both hosts
   - `~/.ssh/id_gcp` private key on each host
   - `~/.ssh/config` for promptless SSH between hosts

## SSH Access

From your local machine:
```bash
ssh -i id_gcp laird@<external-ip>
```

From either instance to the other:
```bash
ssh kind
ssh kindspot
```

No password or host key prompts — both hosts are preconfigured for mutual access.

## Teardown

```bash
terraform destroy
```
