#!/usr/bin/env bash
# Report estimated GCP costs for the free-kind terraform project
set -euo pipefail
cd "$(dirname "$0")"

# --- GCP pricing (us-west1, as of 2025) ---
# e2-micro: $0.00838/hr on-demand
# e2-micro spot: ~$0.00251/hr (typically ~70% discount)
# pd-standard: $0.040/GB/month
# External IP (attached to running VM): $0.004/hr  (previously free, now charged)
# External IP (static, unattached): $0.010/hr
# VPC / firewall rules: free
# Free tier: 1x e2-micro in us regions (720 hrs/mo), 30GB pd-standard, 1GB egress

E2MICRO_HOURLY=0.00838
E2MICRO_SPOT_HOURLY=0.00251
PD_STD_PER_GB_MONTH=0.040
EXT_IP_HOURLY=0.004

# --- Read terraform state ---
if ! terraform state list &>/dev/null; then
  echo "ERROR: No terraform state found. Run 'terraform apply' first."
  exit 1
fi

KIND_STATE=$(terraform state show google_compute_instance.kind 2>/dev/null)
KINDSPOT_STATE=$(terraform state show google_compute_instance.kindspot 2>/dev/null)

KIND_TYPE=$(echo "$KIND_STATE" | awk -F'"' '/machine_type/{print $2}')
KINDSPOT_TYPE=$(echo "$KINDSPOT_STATE" | awk -F'"' '/machine_type/{print $2}')
KIND_DISK=$(echo "$KIND_STATE" | grep 'size' | awk -F'= ' '{print $2}' | tr -d ' ')
KINDSPOT_DISK=$(echo "$KINDSPOT_STATE" | grep 'size' | awk -F'= ' '{print $2}' | tr -d ' ')
KIND_IP=$(terraform output -raw kind_external_ip 2>/dev/null || echo "none")
KINDSPOT_IP=$(terraform output -raw kindspot_external_ip 2>/dev/null || echo "none")

HOURS_PER_DAY=24
HOURS_PER_MONTH=730
DAYS_PER_MONTH=30.4

echo "=============================================="
echo " GCP Cost Report: free-kind project"
echo "=============================================="
echo ""
echo "Resources from Terraform state:"
echo "  kind:     ${KIND_TYPE}  disk=${KIND_DISK}GB  ip=${KIND_IP}"
echo "  kindspot: ${KINDSPOT_TYPE} (spot)  disk=${KINDSPOT_DISK}GB  ip=${KINDSPOT_IP}"
echo ""

# --- Compute costs ---
kind_compute_daily=$(echo "$E2MICRO_HOURLY * $HOURS_PER_DAY" | bc -l)
kind_compute_monthly=$(echo "$E2MICRO_HOURLY * $HOURS_PER_MONTH" | bc -l)

kindspot_compute_daily=$(echo "$E2MICRO_SPOT_HOURLY * $HOURS_PER_DAY" | bc -l)
kindspot_compute_monthly=$(echo "$E2MICRO_SPOT_HOURLY * $HOURS_PER_MONTH" | bc -l)

# --- Disk costs ---
kind_disk_monthly=$(echo "$KIND_DISK * $PD_STD_PER_GB_MONTH" | bc -l)
kind_disk_daily=$(echo "$kind_disk_monthly / $DAYS_PER_MONTH" | bc -l)

kindspot_disk_monthly=$(echo "$KINDSPOT_DISK * $PD_STD_PER_GB_MONTH" | bc -l)
kindspot_disk_daily=$(echo "$kindspot_disk_monthly / $DAYS_PER_MONTH" | bc -l)

# --- External IP costs ---
ip_daily=$(echo "$EXT_IP_HOURLY * $HOURS_PER_DAY" | bc -l)
ip_monthly=$(echo "$EXT_IP_HOURLY * $HOURS_PER_MONTH" | bc -l)
total_ip_daily=$(echo "$ip_daily * 2" | bc -l)
total_ip_monthly=$(echo "$ip_monthly * 2" | bc -l)

# --- Free tier credits ---
# 1x e2-micro (720 hrs) + 30GB pd-standard per month
free_compute_monthly=$kind_compute_monthly
free_disk_monthly=$(echo "30 * $PD_STD_PER_GB_MONTH" | bc -l)
free_compute_daily=$(echo "$free_compute_monthly / $DAYS_PER_MONTH" | bc -l)
free_disk_daily=$(echo "$free_disk_monthly / $DAYS_PER_MONTH" | bc -l)

# --- Totals ---
total_daily=$(echo "$kind_compute_daily + $kindspot_compute_daily + $kind_disk_daily + $kindspot_disk_daily + $total_ip_daily" | bc -l)
total_monthly=$(echo "$kind_compute_monthly + $kindspot_compute_monthly + $kind_disk_monthly + $kindspot_disk_monthly + $total_ip_monthly" | bc -l)

free_daily=$(echo "$free_compute_daily + $free_disk_daily" | bc -l)
free_monthly=$(echo "$free_compute_monthly + $free_disk_monthly" | bc -l)

net_daily=$(echo "$total_daily - $free_daily" | bc -l)
net_monthly=$(echo "$total_monthly - $free_monthly" | bc -l)

printf "%-35s %10s %10s\n" "Cost Breakdown" "Daily" "Monthly"
echo "--------------------------------------------------------------"
printf "%-35s %9s %9s\n" "" "(USD)" "(USD)"
echo ""
printf "%-35s %10.4f %10.2f\n" "kind compute (e2-micro on-demand)" "$kind_compute_daily" "$kind_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "kindspot compute (e2-micro spot)" "$kindspot_compute_daily" "$kindspot_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "kind disk (${KIND_DISK}GB pd-standard)" "$kind_disk_daily" "$kind_disk_monthly"
printf "%-35s %10.4f %10.2f\n" "kindspot disk (${KINDSPOT_DISK}GB pd-standard)" "$kindspot_disk_daily" "$kindspot_disk_monthly"
printf "%-35s %10.4f %10.2f\n" "External IPs (2x attached)" "$total_ip_daily" "$total_ip_monthly"
echo "--------------------------------------------------------------"
printf "%-35s %10.4f %10.2f\n" "GROSS TOTAL" "$total_daily" "$total_monthly"
echo ""
printf "%-35s %10.4f %10.2f\n" "Free tier credit (1x e2-micro)" "-$free_compute_daily" "-$free_compute_monthly"
printf "%-35s %10.4f %10.2f\n" "Free tier credit (30GB disk)" "-$free_disk_daily" "-$free_disk_monthly"
echo "--------------------------------------------------------------"
printf "\033[1m%-35s %10.4f %10.2f\033[0m\n" "ESTIMATED NET COST" "$net_daily" "$net_monthly"
echo ""
echo "Notes:"
echo "  - Free tier: 1x e2-micro (720 hrs/mo) + 30GB pd-standard in us regions"
echo "  - Spot pricing varies; estimate uses ~70% discount off on-demand"
echo "  - External IP charges apply since Feb 2024 (\$0.004/hr per attached IP)"
echo "  - Network egress not included (1GB/mo free, then \$0.12/GB)"
echo "  - Prices based on us-west1; may vary slightly by region"
