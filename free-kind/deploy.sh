#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Initializing Terraform ==="
terraform init

echo "=== Applying Terraform ==="
terraform apply -auto-approve

# Extract IPs from terraform output
KIND_EXT=$(terraform output -raw kind_external_ip)
KIND_INT=$(terraform output -raw kind_internal_ip)
KINDSPOT_EXT=$(terraform output -raw kindspot_external_ip)
KINDSPOT_INT=$(terraform output -raw kindspot_internal_ip)

echo "=== Instance IPs ==="
echo "kind:     external=$KIND_EXT  internal=$KIND_INT"
echo "kindspot: external=$KINDSPOT_EXT  internal=$KINDSPOT_INT"

# Generate Ansible inventory
cat > inventory.ini <<EOF
[kind_hosts]
kind     ansible_host=${KIND_EXT} internal_ip=${KIND_INT}
kindspot ansible_host=${KINDSPOT_EXT} internal_ip=${KINDSPOT_INT}
EOF

echo "=== Clearing stale host keys ==="
for host in "$KIND_EXT" "$KINDSPOT_EXT"; do
  ssh-keygen -R "$host" 2>/dev/null || true
done

echo "=== Waiting for SSH to become available ==="
for host in "$KIND_EXT" "$KINDSPOT_EXT"; do
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
echo "SSH to kind:     ssh -i id_gcp laird@${KIND_EXT}"
echo "SSH to kindspot: ssh -i id_gcp laird@${KINDSPOT_EXT}"
