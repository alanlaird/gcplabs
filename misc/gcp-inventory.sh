#!/usr/bin/env bash
# gcp-inventory.sh — list orgs, folders, projects, resources, and rough monthly costs
# for the currently authenticated gcloud account.
#
# Usage:
#   ./gcp-inventory.sh              # full inventory
#   ./gcp-inventory.sh --projects   # projects + resources only (skip org/folder tree)
#
# Requirements: gcloud SDK + jq, authenticated via:
#   gcloud auth login alan.laird@gmail.com

set -uo pipefail

ACCOUNT="alan.laird@gmail.com"
PROJECTS_ONLY=false

# Running cost total (in cents to avoid floating-point bash issues; printed as dollars)
TOTAL_CENTS=0

# ── helpers ─────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
head2() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
head3() { printf '\n\033[0;33m--- %s ---\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
cost()  { printf '  \033[32m💲 %s\033[0m\n' "$*"; }   # green cost line
warn()  { printf '  \033[33m⚠ %s\033[0m\n' "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "✗ '$1' not found. Install the Google Cloud SDK."; exit 1; }
}

# Safe jq-length: returns 0 on any failure rather than crashing
jqlen() { echo "$1" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null | head -1 || echo 0; }

# Add cents to total
add_cost() { TOTAL_CENTS=$(( TOTAL_CENTS + ${1:-0} )); }

# Format cents as "$X.XX/mo"
fmt_cost() { printf '$%d.%02d/mo' $(( ${1:-0} / 100 )) $(( ${1:-0} % 100 )); }

# ── pricing tables (us-central1, on-demand, approximate) ─────────────────────
# Returns monthly cost in cents for a given machine type.
# Spot/preemptible flag applies ~80% discount.
vm_cost_cents() {
  local mtype="${1:-unknown}"
  local preemptible="${2:-false}"
  local cents=0
  case "$mtype" in
    f1-micro)           cents=551  ;;
    g1-small)           cents=1452 ;;
    e2-micro)           cents=608  ;;
    e2-small)           cents=1217 ;;
    e2-medium)          cents=2433 ;;
    e2-standard-2)      cents=4861 ;;
    e2-standard-4)      cents=9722 ;;
    e2-standard-8)      cents=19444;;
    e2-standard-16)     cents=38888;;
    e2-highcpu-2)       cents=3778 ;;
    e2-highcpu-4)       cents=7556 ;;
    e2-highmem-2)       cents=6461 ;;
    e2-highmem-4)       cents=12922;;
    n1-standard-1)      cents=3447 ;;
    n1-standard-2)      cents=6894 ;;
    n1-standard-4)      cents=13788;;
    n1-standard-8)      cents=27576;;
    n1-standard-16)     cents=55152;;
    n2-standard-2)      cents=7085 ;;
    n2-standard-4)      cents=14171;;
    n2-standard-8)      cents=28342;;
    n2d-standard-2)     cents=6461 ;;
    n2d-standard-4)     cents=12922;;
    t2d-standard-1)     cents=2973 ;;
    t2d-standard-2)     cents=5946 ;;
    t2a-standard-1)     cents=2556 ;;
    c2-standard-4)      cents=19084;;
    c2-standard-8)      cents=38168;;
    *)                  cents=3000 ;;  # unknown → assume ~n1-standard-1 equivalent
  esac
  # Spot/preemptible: ~80% discount
  if [[ "$preemptible" == "true" ]]; then
    cents=$(( cents * 20 / 100 ))
  fi
  echo "$cents"
}

# Returns monthly cost in cents for a Cloud SQL tier
sql_cost_cents() {
  local tier="${1:-unknown}"
  case "$tier" in
    db-f1-micro)         echo 800  ;;
    db-g1-small)         echo 2700 ;;
    db-n1-standard-1)    echo 4600 ;;
    db-n1-standard-2)    echo 9200 ;;
    db-n1-standard-4)    echo 18400;;
    db-n1-highmem-2)     echo 11600;;
    db-n1-highmem-4)     echo 23200;;
    db-custom-*)
      # db-custom-<cpus>-<mb> — rough estimate: $23/vCPU/mo
      local cpus; cpus=$(echo "$tier" | cut -d- -f3)
      echo $(( ${cpus:-1} * 2300 ))
      ;;
    *)                   echo 4600 ;;  # unknown → n1-standard-1 equivalent
  esac
}

[[ "${1:-}" == "--projects" ]] && PROJECTS_ONLY=true

require gcloud
require jq

# ── verify active account ────────────────────────────────────────────────────
bold "GCP Inventory — ${ACCOUNT}"
printf 'Generated: %s\n' "$(date)"
printf '(Cost estimates are rough us-central1 on-demand rates; actual bills may differ)\n'

ACTIVE=$(gcloud config get-value account 2>/dev/null || true)
if [[ "$ACTIVE" != "$ACCOUNT" ]]; then
  warn "Active account is '${ACTIVE}', not '${ACCOUNT}'."
  warn "Run: gcloud config set account ${ACCOUNT}"
  warn "Continuing with active account '${ACTIVE}'..."
fi

# ── organizations ────────────────────────────────────────────────────────────
if ! $PROJECTS_ONLY; then
  head2 "Organizations"
  ORGS=$(gcloud organizations list --format="json" 2>/dev/null || echo "[]")
  ORG_COUNT=$(jqlen "$ORGS")

  if [[ "$ORG_COUNT" -eq 0 ]]; then
    info "(no organizations — personal/consumer account)"
  else
    echo "$ORGS" | jq -r '.[] | "  \(.displayName)  [\(.name)]  domain=\(.owner.directoryCustomerId // "n/a")"'
  fi

  # ── folders ───────────────────────────────────────────────────────────────
  head2 "Folders"
  if [[ "$ORG_COUNT" -gt 0 ]]; then
    echo "$ORGS" | jq -r '.[].name' | while read -r org; do
      gcloud resource-manager folders list --organization="${org#organizations/}" \
        --format="table(displayName, name, lifecycleState)" 2>/dev/null || true
    done
  else
    info "(no folders)"
  fi
fi

# ── projects ─────────────────────────────────────────────────────────────────
head2 "Projects"
PROJECTS=$(gcloud projects list \
  --filter="lifecycleState=ACTIVE" \
  --format="json" \
  --sort-by="projectId" 2>/dev/null || echo "[]")

PROJECT_COUNT=$(jqlen "$PROJECTS")
info "Total active projects: ${PROJECT_COUNT}"

echo "$PROJECTS" | jq -r '.[] |
  "  \(.projectId)  (\(.name))  #\(.projectNumber)  parent=\(.parent.type // "none")/\(.parent.id // "n/a")"'

# ── per-project resources ────────────────────────────────────────────────────
head2 "Resources per Project"

while IFS= read -r PROJECT <&3; do
  head3 "${PROJECT}"
  PROJECT_CENTS=0

  # ── Compute instances ─────────────────────────────────────────────────────
  INSTANCES=$(gcloud compute instances list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$INSTANCES")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Compute instances (${COUNT}):"
    while IFS=$'\t' read -r name zone mtype status preempt; do
      cents=$(vm_cost_cents "$mtype" "$preempt")
      PROJECT_CENTS=$(( PROJECT_CENTS + cents ))
      spot_label=""
      [[ "$preempt" == "true" ]] && spot_label=" [SPOT]"
      printf '    %-30s  zone=%-20s  type=%-18s  status=%-10s  ~%s\n' \
        "$name" "$zone" "${mtype}${spot_label}" "$status" "$(fmt_cost "$cents")"
    done < <(echo "$INSTANCES" | jq -r \
      '.[] | [
        .name,
        (.zone | split("/") | last),
        (.machineType | split("/") | last),
        .status,
        ((.scheduling.preemptible // false) | tostring)
      ] | @tsv')
  fi

  # ── GKE clusters ──────────────────────────────────────────────────────────
  CLUSTERS=$(gcloud container clusters list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$CLUSTERS")
  if [[ "$COUNT" -gt 0 ]]; then
    info "GKE clusters (${COUNT}):"
    # GKE fee: $0.10/hr/cluster = $73/mo (zonal); 0 for Autopilot free tier
    # Node costs are counted separately under compute instances.
    GKE_FEE_CENTS=7300
    PROJECT_CENTS=$(( PROJECT_CENTS + COUNT * GKE_FEE_CENTS ))
    echo "$CLUSTERS" | jq -r \
      '.[] | "    \(.name)  location=\(.location)  nodes=\(.currentNodeCount // "?")  version=\(.currentMasterVersion // "?")  status=\(.status)"'
    printf '    (GKE management fee: ~%s per cluster)\n' "$(fmt_cost $GKE_FEE_CENTS)"
  fi

  # ── Cloud Storage ─────────────────────────────────────────────────────────
  BUCKETS=$(gcloud storage buckets list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$BUCKETS")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Storage buckets (${COUNT}):"
    echo "$BUCKETS" | jq -r '.[] | "    \(.name)  location=\(.location // "?")  class=\(.storageClass // "?")"'
    info "  (Storage cost: ~\$0.020/GB/mo standard — size not queried)"
  fi

  # ── Cloud SQL ─────────────────────────────────────────────────────────────
  SQL=$(gcloud sql instances list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$SQL")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Cloud SQL instances (${COUNT}):"
    while IFS=$'\t' read -r name tier region state; do
      cents=$(sql_cost_cents "$tier")
      PROJECT_CENTS=$(( PROJECT_CENTS + cents ))
      printf '    %-28s  tier=%-22s  region=%-15s  state=%-10s  ~%s\n' \
        "$name" "$tier" "$region" "$state" "$(fmt_cost "$cents")"
    done < <(echo "$SQL" | jq -r \
      '.[] | [.name, .settings.tier, .region, .state] | @tsv')
  fi

  # ── Cloud Run ─────────────────────────────────────────────────────────────
  RUN=$(gcloud run services list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$RUN")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Cloud Run services (${COUNT}):"
    echo "$RUN" | jq -r \
      '.[] | "    \(.metadata.name)  region=\(.metadata.labels."cloud.googleapis.com/location" // "n/a")"'
    info "  (Cloud Run cost: ~\$0 at low traffic; ~\$0.00002400/vCPU-sec at scale)"
  fi

  # ── Artifact Registry ─────────────────────────────────────────────────────
  AR=$(gcloud artifacts repositories list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$AR")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Artifact Registry repos (${COUNT}):"
    echo "$AR" | jq -r \
      '.[] | "    \(.name | split("/") | last)  format=\(.format)  location=\(.name | split("/")[3])"'
    info "  (AR cost: ~\$0.10/GB/mo stored; first 0.5 GB/mo free)"
  fi

  # ── Billing ───────────────────────────────────────────────────────────────
  BILLING=$(gcloud billing projects describe "$PROJECT" \
    --format="value(billingAccountName,billingEnabled)" 2>/dev/null </dev/null || echo "n/a")
  info "Billing: ${BILLING}"

  # ── Project cost subtotal ─────────────────────────────────────────────────
  cost "Estimated project cost: ~$(fmt_cost $PROJECT_CENTS)"
  add_cost "$PROJECT_CENTS"

done 3< <(echo "$PROJECTS" | jq -r '.[].projectId')

# ── Grand total ───────────────────────────────────────────────────────────────
printf '\n\033[1;32m'
printf '══════════════════════════════════════════════════\n'
printf '  TOTAL PROJECTED MONTHLY COST: ~%s\n' "$(fmt_cost $TOTAL_CENTS)"
printf '══════════════════════════════════════════════════\n'
printf '\033[0m'
printf 'Notes:\n'
printf '  • Rates are approximate us-central1 on-demand prices (Mar 2026)\n'
printf '  • Spot/preemptible instances shown with 80%% discount applied\n'
printf '  • Storage (GCS, AR, SQL disk) excluded — size not queried\n'
printf '  • Cloud Run, Pub/Sub, BigQuery, etc. are usage-based and excluded\n'
printf '  • For exact costs use: https://console.cloud.google.com/billing\n'
printf '\n✓ Done\n'
