#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Initializing Terraform ==="
terraform init

echo "=== Applying Terraform ==="
terraform apply -auto-approve

# Extract IPs from terraform output
KIND1_EXT=$(terraform output -raw kind1_external_ip)
KIND1_INT=$(terraform output -raw kind1_internal_ip)
KIND2_EXT=$(terraform output -raw kind2_external_ip)
KIND2_INT=$(terraform output -raw kind2_internal_ip)
KIND3_EXT=$(terraform output -raw kind3_external_ip)
KIND3_INT=$(terraform output -raw kind3_internal_ip)

echo "=== Instance IPs ==="
echo "kind1: external=$KIND1_EXT  internal=$KIND1_INT"
echo "kind2: external=$KIND2_EXT  internal=$KIND2_INT"
echo "kind3: external=$KIND3_EXT  internal=$KIND3_INT"

# Generate Ansible inventory
cat > inventory.ini <<EOF
[control_plane]
kind1 ansible_host=${KIND1_EXT} internal_ip=${KIND1_INT}

[workers]
kind2 ansible_host=${KIND2_EXT} internal_ip=${KIND2_INT}
kind3 ansible_host=${KIND3_EXT} internal_ip=${KIND3_INT}

[kind_hosts:children]
control_plane
workers
EOF

echo "=== Clearing stale host keys ==="
for host in "$KIND1_EXT" "$KIND2_EXT" "$KIND3_EXT"; do
  ssh-keygen -R "$host" 2>/dev/null || true
done

echo "=== Waiting for SSH to become available ==="
for host in "$KIND1_EXT" "$KIND2_EXT" "$KIND3_EXT"; do
  for i in $(seq 1 30); do
    if ssh -i id_gcp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 laird@"$host" true 2>/dev/null; then
      echo "  $host: SSH ready"
      break
    fi
    echo "  $host: attempt $i/30..."
    sleep 5
  done
done

echo "=== Running Ansible Playbook ==="
ansible-playbook playbook.yml

echo "=== Done ==="
echo "SSH to kind1: ssh -i id_gcp laird@${KIND1_EXT}"
echo "SSH to kind2: ssh -i id_gcp laird@${KIND2_EXT}"
echo "SSH to kind3: ssh -i id_gcp laird@${KIND3_EXT}"
