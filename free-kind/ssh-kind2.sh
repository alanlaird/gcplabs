#!/usr/bin/env bash
cd "$(dirname "$0")"
exec ssh -i id_gcp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  laird@"$(terraform output -raw kind2_external_ip)" "$@"
