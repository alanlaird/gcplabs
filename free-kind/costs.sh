#!/usr/bin/env bash
# Report estimated GCP costs for the free-kind terraform project
set -euo pipefail
cd "$(dirname "$0")"

# --- GCP pricing (us-west1, as of 2025) ---
# e2-standard-2 spot: ~$0.02010/hr (typically ~70% discount off $0.06710)
# pd-standard: $0.040/GB/month
# External IP (attached to running VM): $0.004/hr
# VPC / firewall rules: free
# Free tier: 1x e2-micro in us regions (720 hrs/mo), 30GB pd-standard, 1GB egress

E2STD2_SPOT_HOURLY=0.02010
PD_STD_PER_GB_MONTH=0.040
EXT_IP_HOURLY=0.004

# --- Read terraform state ---
if ! terraform state list &>/dev/null; then
  echo "ERROR: No terraform state found. Run 'terraform apply' first."
  exit 1
fi

KIND1_STATE=$(terraform state show google_compute_instance.kind1 2>/dev/null)
KIND2_STATE=$(terraform state show google_compute_instance.kind2 2>/dev/null)
KIND3_STATE=$(terraform state show google_compute_instance.kind3 2>/dev/null)

KIND1_TYPE=$(echo "$KIND1_STATE" | awk -F'"' '/machine_type/{print $2}')
KIND2_TYPE=$(echo "$KIND2_STATE" | awk -F'"' '/machine_type/{print $2}')
KIND3_TYPE=$(echo "$KIND3_STATE" | awk -F'"' '/machine_type/{print $2}')
KIND1_DISK=$(echo "$KIND1_STATE" | grep 'size' | awk -F'= ' '{print $2}' | tr -d ' ')
KIND2_DISK=$(echo "$KIND2_STATE" | grep 'size' | awk -F'= ' '{print $2}' | tr -d ' ')
KIND3_DISK=$(echo "$KIND3_STATE" | grep 'size' | awk -F'= ' '{print $2}' | tr -d ' ')
KIND1_IP=$(terraform output -raw kind1_external_ip 2>/dev/null || echo "none")
KIND2_IP=$(terraform output -raw kind2_external_ip 2>/dev/null || echo "none")
KIND3_IP=$(terraform output -raw kind3_external_ip 2>/dev/null || echo "none")

HOURS_PER_DAY=24
HOURS_PER_MONTH=730
DAYS_PER_MONTH=30.4

echo "=============================================="
echo " GCP Cost Report: free-kind project"
echo "=============================================="
echo ""
echo "Resources from Terraform state:"
echo "  kind1: ${KIND1_TYPE} (spot)  disk=${KIND1_DISK}GB  ip=${KIND1_IP}"
echo "  kind2: ${KIND2_TYPE} (spot)  disk=${KIND2_DISK}GB  ip=${KIND2_IP}"
echo "  kind3: ${KIND3_TYPE} (spot)  disk=${KIND3_DISK}GB  ip=${KIND3_IP}"
echo ""

# --- Compute costs (all spot) ---
kind1_compute_daily=$(echo "$E2STD2_SPOT_HOURLY * $HOURS_PER_DAY" | bc -l)
kind1_compute_monthly=$(echo "$E2STD2_SPOT_HOURLY * $HOURS_PER_MONTH" | bc -l)

kind2_compute_daily=$(echo "$E2STD2_SPOT_HOURLY * $HOURS_PER_DAY" | bc -l)
kind2_compute_monthly=$(echo "$E2STD2_SPOT_HOURLY * $HOURS_PER_MONTH" | bc -l)

kind3_compute_daily=$(echo "$E2STD2_SPOT_HOURLY * $HOURS_PER_DAY" | bc -l)
kind3_compute_monthly=$(echo "$E2STD2_SPOT_HOURLY * $HOURS_PER_MONTH" | bc -l)

# --- Disk costs ---
kind1_disk_monthly=$(echo "$KIND1_DISK * $PD_STD_PER_GB_MONTH" | bc -l)
kind1_disk_daily=$(echo "$kind1_disk_monthly / $DAYS_PER_MONTH" | bc -l)

kind2_disk_monthly=$(echo "$KIND2_DISK * $PD_STD_PER_GB_MONTH" | bc -l)
kind2_disk_daily=$(echo "$kind2_disk_monthly / $DAYS_PER_MONTH" | bc -l)

kind3_disk_monthly=$(echo "$KIND3_DISK * $PD_STD_PER_GB_MONTH" | bc -l)
kind3_disk_daily=$(echo "$kind3_disk_monthly / $DAYS_PER_MONTH" | bc -l)

# --- External IP costs ---
ip_daily=$(echo "$EXT_IP_HOURLY * $HOURS_PER_DAY" | bc -l)
ip_monthly=$(echo "$EXT_IP_HOURLY * $HOURS_PER_MONTH" | bc -l)
total_ip_daily=$(echo "$ip_daily * 3" | bc -l)
total_ip_monthly=$(echo "$ip_monthly * 3" | bc -l)

# --- Free tier credits ---
# 1x e2-micro (720 hrs) + 30GB pd-standard per month
# Note: free tier applies to on-demand pricing ($0.00838/hr), not spot
free_compute_monthly=$(echo "0.00838 * 730" | bc -l)
free_disk_monthly=$(echo "30 * $PD_STD_PER_GB_MONTH" | bc -l)
free_compute_daily=$(echo "$free_compute_monthly / $DAYS_PER_MONTH" | bc -l)
free_disk_daily=$(echo "$free_disk_monthly / $DAYS_PER_MONTH" | bc -l)

# --- Totals ---
total_daily=$(echo "$kind1_compute_daily + $kind2_compute_daily + $kind3_compute_daily + $kind1_disk_daily + $kind2_disk_daily + $kind3_disk_daily + $total_ip_daily" | bc -l)
total_monthly=$(echo "$kind1_compute_monthly + $kind2_compute_monthly + $kind3_compute_monthly + $kind1_disk_monthly + $kind2_disk_monthly + $kind3_disk_monthly + $total_ip_monthly" | bc -l)

free_daily=$(echo "$free_compute_daily + $free_disk_daily" | bc -l)
free_monthly=$(echo "$free_compute_monthly + $free_disk_monthly" | bc -l)

net_daily=$(echo "$total_daily - $free_daily" | bc -l)
net_monthly=$(echo "$total_monthly - $free_monthly" | bc -l)

printf "%-35s %10s %10s\n" "Cost Breakdown" "Daily" "Monthly"
echo "--------------------------------------------------------------"
printf "%-35s %9s %9s\n" "" "(USD)" "(USD)"
echo ""
printf "%-35s %10.4f %10.2f\n" "kind1 compute (e2-standard-2 spot)" "$kind1_compute_daily" "$kind1_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "kind2 compute (e2-standard-2 spot)" "$kind2_compute_daily" "$kind2_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "kind3 compute (e2-standard-2 spot)" "$kind3_compute_daily" "$kind3_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "kind1 disk (${KIND1_DISK}GB pd-standard)" "$kind1_disk_daily" "$kind1_disk_monthly"
printf "%-35s %10.4f %10.2f\n" "kind2 disk (${KIND2_DISK}GB pd-standard)" "$kind2_disk_daily" "$kind2_disk_monthly"
printf "%-35s %10.4f %10.2f\n" "kind3 disk (${KIND3_DISK}GB pd-standard)" "$kind3_disk_daily" "$kind3_disk_monthly"
printf "%-35s %10.4f %10.2f\n" "External IPs (3x attached)" "$total_ip_daily" "$total_ip_monthly"
echo "--------------------------------------------------------------"
printf "%-35s %10.4f %10.2f\n" "GROSS TOTAL" "$total_daily" "$total_monthly"
echo ""
printf "%-35s %10.4f %10.2f\n" "Free tier credit (1x e2-micro)" "-$free_compute_daily" "-$free_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "Free tier credit (30GB disk)" "-$free_disk_daily" "-$free_disk_monthly"
echo "--------------------------------------------------------------"
printf "\033[1m%-35s %10.4f %10.2f\033[0m\n" "ESTIMATED NET COST" "$net_daily" "$net_monthly"
echo ""
echo "Notes:"
echo "  - All instances are spot/preemptible (may be reclaimed by GCP)"
echo "  - Free tier: 1x e2-micro (720 hrs/mo) + 30GB pd-standard in us regions"
echo "  - Spot pricing varies; estimate uses ~70% discount off on-demand"
echo "  - External IP charges apply since Feb 2024 (\$0.004/hr per attached IP)"
echo "  - Network egress not included (1GB/mo free, then \$0.12/GB)"
echo "  - Prices based on us-west1; may vary slightly by region"
