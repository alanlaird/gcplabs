#!/usr/bin/env python3

"""
GKE Project Resource Billing Script
- Uses Google Cloud APIs to list all GCP resources in the project
- Estimates daily and monthly costs for each resource type (GKE control plane, node VMs, disks, LB, logging/monitoring, etc.)

Requirements:
  pip install google-auth google-api-python-client tabulate
  gcloud auth application-default login

Usage:
  python3 scripts/gke_billing_report.py --project <PROJECT_ID> [--region <REGION>]
"""


import argparse
import os
from googleapiclient import discovery
from google.auth import default
from tabulate import tabulate

# Constants
HOURS_PER_DAY = 24
DAYS_PER_MONTH = 30.44  # Average month

# Static pricing tables (as of Feb 2026, update as needed)
GKE_CONTROL_PLANE_COST_PER_HOUR = 0.10  # USD per hour (zonal cluster)
PREEMPTIBLE_VCPU_COST_PER_HOUR = 0.0106  # USD per vCPU per hour
PREEMPTIBLE_MEM_COST_PER_HOUR = 0.0009   # USD per GB per hour
DISK_COST_PER_GB_MONTH = 0.017  # Standard PD, USD per GB per month
LB_COST_PER_HOUR = 0.025  # USD per hour for forwarding rule
LB_DATA_COST_PER_GB = 0.008  # USD per GB (intra-region)
LOGGING_MONITORING_COST_PER_GB = 0.50  # USD per GB (estimate, may vary)

def get_gke_clusters(container, project_id, region):
  clusters = []
  req = container.projects().locations().clusters().list(parent=f"projects/{project_id}/locations/{region}")
  resp = req.execute()
  for c in resp.get('clusters', []):
    clusters.append(c)
  return clusters

def get_node_pools(container, project_id, region, cluster_name):
  node_pools = []
  req = container.projects().locations().clusters().nodePools().list(parent=f"projects/{project_id}/locations/{region}/clusters/{cluster_name}")
  resp = req.execute()
  for np in resp.get('nodePools', []):
    node_pools.append(np)
  return node_pools

def get_compute_instances(compute, project_id, region):
  # List all instances in all zones in the region
  result = []
  zones_req = compute.zones().list(project=project_id)
  zones = [z['name'] for z in zones_req.execute().get('items', []) if z['name'].startswith(region)]
  for zone in zones:
    req = compute.instances().list(project=project_id, zone=zone)
    resp = req.execute()
    for inst in resp.get('items', []):
      result.append(inst)
  return result

def get_disks(compute, project_id, region):
  # List all disks in all zones in the region
  result = []
  zones_req = compute.zones().list(project=project_id)
  zones = [z['name'] for z in zones_req.execute().get('items', []) if z['name'].startswith(region)]
  for zone in zones:
    req = compute.disks().list(project=project_id, zone=zone)
    resp = req.execute()
    for disk in resp.get('items', []):
      result.append(disk)
  return result

def get_forwarding_rules(compute, project_id, region):
  # List all forwarding rules (load balancers) in the region
  req = compute.forwardingRules().list(project=project_id, region=region)
  resp = req.execute()
  return resp.get('items', [])

def main():
  parser = argparse.ArgumentParser(description="GKE Project Resource Billing Calculator")
  parser.add_argument('--project', help='GCP Project ID (default: from PROJECT_ID env)')
  parser.add_argument('--region', default='us-central1', help='GCP Region (default: us-central1)')
  args = parser.parse_args()

  project_id = args.project or os.environ.get('PROJECT_ID')
  if not project_id:
    raise SystemExit("Error: GCP project ID must be provided via --project or PROJECT_ID environment variable.")
  region = args.region

  creds, _ = default()
  compute = discovery.build('compute', 'v1', credentials=creds)
  container = discovery.build('container', 'v1', credentials=creds)

  # 1. GKE Clusters (control plane cost)
  clusters = get_gke_clusters(container, project_id, region)
  gke_rows = []
  for c in clusters:
    name = c['name']
    gke_rows.append([
      name,
      f"${GKE_CONTROL_PLANE_COST_PER_HOUR*HOURS_PER_DAY:.2f}",
      f"${GKE_CONTROL_PLANE_COST_PER_HOUR*HOURS_PER_DAY*DAYS_PER_MONTH:.2f}"
    ])

  # 2. Node Pools (VMs)
  node_rows = []
  for c in clusters:
    node_pools = get_node_pools(container, project_id, region, c['name'])
    for np in node_pools:
      config = np['config']
      machine_type = config['machineType']
      preemptible = config.get('preemptible', False)
      node_count = np['initialNodeCount']
      vcpus = 2  # default for e2-medium, else fetch from API
      mem_gb = 4 # default for e2-medium, else fetch from API
      if machine_type == 'e2-medium':
        vcpus, mem_gb = 2, 4
      # TODO: For other types, fetch from API
      price_per_hour = vcpus * PREEMPTIBLE_VCPU_COST_PER_HOUR + mem_gb * PREEMPTIBLE_MEM_COST_PER_HOUR
      daily = price_per_hour * HOURS_PER_DAY * node_count
      monthly = price_per_hour * HOURS_PER_DAY * DAYS_PER_MONTH * node_count
      node_rows.append([
        machine_type + (" (preemptible)" if preemptible else ""),
        vcpus,
        mem_gb,
        node_count,
        f"${price_per_hour:.4f}",
        f"${daily:.2f}",
        f"${monthly:.2f}"
      ])

  # 3. Disks
  disks = get_disks(compute, project_id, region)
  disk_rows = []
  for d in disks:
    size_gb = d['sizeGb']
    daily = (float(size_gb) * DISK_COST_PER_GB_MONTH) / DAYS_PER_MONTH
    monthly = float(size_gb) * DISK_COST_PER_GB_MONTH
    disk_rows.append([
      d['name'],
      size_gb,
      f"${daily:.2f}",
      f"${monthly:.2f}"
    ])

  # 4. Load Balancers (Forwarding Rules)
  lbs = get_forwarding_rules(compute, project_id, region)
  lb_rows = []
  for lb in lbs:
    daily = LB_COST_PER_HOUR * HOURS_PER_DAY
    monthly = LB_COST_PER_HOUR * HOURS_PER_DAY * DAYS_PER_MONTH
    lb_rows.append([
      lb['name'],
      f"${daily:.2f}",
      f"${monthly:.2f}"
    ])

  # Print summary tables
  print("\nGKE Control Plane (per cluster):")
  print(tabulate(gke_rows, headers=["Cluster Name", "$ per day", "$ per month"], tablefmt="github"))

  print("\nNode Pools:")
  print(tabulate(node_rows, headers=["Machine Type", "vCPUs", "RAM (GB)", "Nodes", "Spot $/hr", "$ per day", "$ per month"], tablefmt="github"))

  print("\nPersistent Disks:")
  print(tabulate(disk_rows, headers=["Disk Name", "Size (GB)", "$ per day", "$ per month"], tablefmt="github"))

  print("\nLoad Balancers (Forwarding Rules):")
  print(tabulate(lb_rows, headers=["LB Name", "$ per day", "$ per month"], tablefmt="github"))

  print("\n*Logging/monitoring, network, and egress costs are not fully itemized here. See GCP pricing docs for details.")

if __name__ == "__main__":
  main()

def main():
    parser = argparse.ArgumentParser(description="GKE Spot Instance Billing Calculator")
    parser.add_argument('--project', help='GCP Project ID (default: from PROJECT_ID env)')
    parser.add_argument('--zone', default='us-central1-a', help='GCP Zone (default: us-central1-a)')
    parser.add_argument('--machine_type', default='e2-medium', help='Machine type (default: e2-medium)')
    parser.add_argument('--node_count', type=int, default=1, help='Number of nodes (default: 1)')
    args = parser.parse_args()

    # Use environment variable if --project not provided
    project_id = args.project or os.environ.get('PROJECT_ID')
    if not project_id:
      raise SystemExit("Error: GCP project ID must be provided via --project or PROJECT_ID environment variable.")

    # Authenticate and build compute API client
    creds, _ = default()
    compute = discovery.build('compute', 'v1', credentials=creds)

    # Get spot price


if __name__ == "__main__":
    main()
