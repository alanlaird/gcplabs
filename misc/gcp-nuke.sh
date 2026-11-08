#!/usr/bin/env bash
# gcp-nuke.sh — list GCP resources; optionally delete them
#
# Usage:
#   ./gcp-nuke.sh                   # inventory only (safe)
#   ./gcp-nuke.sh --kill            # inventory + prompt to delete per project
#   ./gcp-nuke.sh --kill --yes      # inventory + delete WITHOUT prompting (DANGER)
#   ./gcp-nuke.sh --projects        # skip org/folder tree
#   ./gcp-nuke.sh --kill --project myproj  # target a single project
#
# What gets deleted with --kill:
#   • Compute instances (all zones)
#   • GKE clusters
#   • Cloud SQL instances
#   • Cloud Run services (all regions)
#   • Artifact Registry repositories
#   • Cloud Storage buckets (only if empty)
#
# Requirements: gcloud SDK + jq

set -uo pipefail

ACCOUNT="alan.laird@gmail.com"
PROJECTS_ONLY=false
KILL=false
AUTO_YES=false
TARGET_PROJECT=""

# ── helpers ──────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
head2() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
head3() { printf '\n\033[0;33m--- %s ---\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '  \033[33m⚠ %s\033[0m\n' "$*" >&2; }
err()   { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found."
}

jqlen() { echo "$1" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null | head -1 || echo 0; }

# Ask yes/no; returns 0 for yes, 1 for no
ask() {
  local prompt="${1:-Continue?}"
  if $AUTO_YES; then return 0; fi
  printf '\n\033[1;31m%s [yes/N]: \033[0m' "$prompt"
  read -r answer
  [[ "$answer" == "yes" ]]
}

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kill)      KILL=true ;;
    --yes)       AUTO_YES=true ;;
    --projects)  PROJECTS_ONLY=true ;;
    --project)   shift; TARGET_PROJECT="${1:-}"; [[ -z "$TARGET_PROJECT" ]] && die "--project requires a value" ;;
    --help|-h)
      sed -n '2,15p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

if $AUTO_YES && ! $KILL; then
  die "--yes requires --kill"
fi

require gcloud
require jq

# ── verify active account ─────────────────────────────────────────────────────
bold "GCP Resource Manager — ${ACCOUNT}"
printf 'Generated: %s\n' "$(date)"
if $KILL; then
  printf '\033[1;31mKILL MODE ENABLED\033[0m — resources will be PERMANENTLY DELETED\n'
fi

ACTIVE=$(gcloud config get-value account 2>/dev/null || true)
if [[ "$ACTIVE" != "$ACCOUNT" ]]; then
  warn "Active account is '${ACTIVE}', expected '${ACCOUNT}'. Continuing..."
fi

# ── organizations / folders ───────────────────────────────────────────────────
if ! $PROJECTS_ONLY && [[ -z "$TARGET_PROJECT" ]]; then
  head2 "Organizations"
  ORGS=$(gcloud organizations list --format="json" 2>/dev/null || echo "[]")
  ORG_COUNT=$(jqlen "$ORGS")
  if [[ "$ORG_COUNT" -eq 0 ]]; then
    info "(no organizations — personal/consumer account)"
  else
    echo "$ORGS" | jq -r '.[] | "  \(.displayName)  [\(.name)]"'
  fi
fi

# ── projects ──────────────────────────────────────────────────────────────────
head2 "Projects"
if [[ -n "$TARGET_PROJECT" ]]; then
  PROJECTS=$(gcloud projects describe "$TARGET_PROJECT" --format="json" 2>/dev/null \
    | jq -s '.' || echo "[]")
else
  PROJECTS=$(gcloud projects list \
    --filter="lifecycleState=ACTIVE" \
    --format="json" \
    --sort-by="projectId" 2>/dev/null || echo "[]")
fi

PROJECT_COUNT=$(jqlen "$PROJECTS")
info "Total active projects: ${PROJECT_COUNT}"
echo "$PROJECTS" | jq -r '.[] | "  \(.projectId)  (\(.name))"'

# ── per-project inventory + optional delete ───────────────────────────────────
head2 "Resources per Project"

while IFS= read -r PROJECT <&3; do
  head3 "${PROJECT}"

  # Arrays to collect deletable resources
  declare -a VM_DELETE=()       # "name zone"
  declare -a GKE_DELETE=()      # "name location"
  declare -a SQL_DELETE=()      # "name"
  declare -a RUN_DELETE=()      # "name region"
  declare -a AR_DELETE=()       # "full repo name"
  declare -a GCS_DELETE=()      # "bucket name"

  # ── Compute instances ────────────────────────────────────────────────────
  INSTANCES=$(gcloud compute instances list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$INSTANCES")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Compute instances (${COUNT}):"
    while IFS=$'\t' read -r name zone mtype status preempt; do
      spot_label=""; [[ "$preempt" == "true" ]] && spot_label=" [SPOT]"
      printf '    %-30s  zone=%-20s  type=%s%s  status=%s\n' \
        "$name" "$zone" "$mtype" "$spot_label" "$status"
      VM_DELETE+=("${name} ${zone}")
    done < <(echo "$INSTANCES" | jq -r \
      '.[] | [.name, (.zone|split("/")|last), (.machineType|split("/")|last),
              .status, ((.scheduling.preemptible//false)|tostring)] | @tsv')
  fi

  # ── GKE clusters ─────────────────────────────────────────────────────────
  CLUSTERS=$(gcloud container clusters list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$CLUSTERS")
  if [[ "$COUNT" -gt 0 ]]; then
    info "GKE clusters (${COUNT}):"
    while IFS=$'\t' read -r name location nodes version status; do
      printf '    %-30s  location=%-20s  nodes=%-4s  version=%s  status=%s\n' \
        "$name" "$location" "$nodes" "$version" "$status"
      GKE_DELETE+=("${name} ${location}")
    done < <(echo "$CLUSTERS" | jq -r \
      '.[] | [.name, .location, (.currentNodeCount//0|tostring),
              (.currentMasterVersion//"?"), .status] | @tsv')
  fi

  # ── Cloud Storage ─────────────────────────────────────────────────────────
  BUCKETS=$(gcloud storage buckets list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$BUCKETS")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Storage buckets (${COUNT}):"
    while IFS=$'\t' read -r name location class; do
      printf '    %-40s  location=%-10s  class=%s\n' "$name" "$location" "$class"
      GCS_DELETE+=("$name")
    done < <(echo "$BUCKETS" | jq -r \
      '.[] | [.name, (.location//"?"), (.storageClass//"?")] | @tsv')
    info "  (buckets will only be deleted if empty)"
  fi

  # ── Cloud SQL ─────────────────────────────────────────────────────────────
  SQL=$(gcloud sql instances list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$SQL")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Cloud SQL instances (${COUNT}):"
    while IFS=$'\t' read -r name tier region state; do
      printf '    %-28s  tier=%-22s  region=%-15s  state=%s\n' \
        "$name" "$tier" "$region" "$state"
      SQL_DELETE+=("$name")
    done < <(echo "$SQL" | jq -r \
      '.[] | [.name, .settings.tier, .region, .state] | @tsv')
  fi

  # ── Cloud Run ─────────────────────────────────────────────────────────────
  RUN=$(gcloud run services list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$RUN")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Cloud Run services (${COUNT}):"
    while IFS=$'\t' read -r name region; do
      printf '    %-30s  region=%s\n' "$name" "$region"
      RUN_DELETE+=("${name} ${region}")
    done < <(echo "$RUN" | jq -r \
      '.[] | [.metadata.name,
              (.metadata.labels."cloud.googleapis.com/location"//"n/a")] | @tsv')
  fi

  # ── Artifact Registry ─────────────────────────────────────────────────────
  AR=$(gcloud artifacts repositories list \
    --project="$PROJECT" --format="json" --quiet 2>/dev/null </dev/null || echo "[]")
  COUNT=$(jqlen "$AR")
  if [[ "$COUNT" -gt 0 ]]; then
    info "Artifact Registry repos (${COUNT}):"
    while IFS=$'\t' read -r fullname format location; do
      local_name="${fullname##*/}"
      printf '    %-30s  format=%-10s  location=%s\n' "$local_name" "$format" "$location"
      AR_DELETE+=("$fullname")
    done < <(echo "$AR" | jq -r \
      '.[] | [.name, .format, (.name|split("/")|.[3])] | @tsv')
  fi

  # ── Kill section ──────────────────────────────────────────────────────────
  TOTAL_RES=$(( ${#VM_DELETE[@]} + ${#GKE_DELETE[@]} + ${#SQL_DELETE[@]} + \
                ${#RUN_DELETE[@]} + ${#AR_DELETE[@]} + ${#GCS_DELETE[@]} ))

  if $KILL && [[ "$TOTAL_RES" -gt 0 ]]; then
    printf '\n  \033[1;31m%d resource(s) found in %s\033[0m\n' "$TOTAL_RES" "$PROJECT"

    if ask "DELETE all ${TOTAL_RES} resource(s) in project '${PROJECT}'?"; then

      # GKE first (nodes are compute instances — delete cluster deletes them)
      for entry in "${GKE_DELETE[@]+"${GKE_DELETE[@]}"}"; do
        name="${entry%% *}"; location="${entry#* }"
        printf '  Deleting GKE cluster %s (%s)...\n' "$name" "$location"
        if gcloud container clusters delete "$name" \
            --project="$PROJECT" --location="$location" --quiet 2>/dev/null; then
          ok "Deleted GKE cluster $name"
        else
          err "Failed to delete GKE cluster $name"
        fi
      done

      # Compute instances (only those NOT managed by GKE above)
      for entry in "${VM_DELETE[@]+"${VM_DELETE[@]}"}"; do
        name="${entry%% *}"; zone="${entry#* }"
        printf '  Deleting compute instance %s (%s)...\n' "$name" "$zone"
        if gcloud compute instances delete "$name" \
            --project="$PROJECT" --zone="$zone" --quiet 2>/dev/null; then
          ok "Deleted instance $name"
        else
          err "Failed (may have been removed by GKE delete): $name"
        fi
      done

      # Cloud SQL
      for name in "${SQL_DELETE[@]+"${SQL_DELETE[@]}"}"; do
        printf '  Deleting Cloud SQL instance %s...\n' "$name"
        if gcloud sql instances delete "$name" \
            --project="$PROJECT" --quiet 2>/dev/null; then
          ok "Deleted SQL instance $name"
        else
          err "Failed to delete SQL instance $name"
        fi
      done

      # Cloud Run
      for entry in "${RUN_DELETE[@]+"${RUN_DELETE[@]}"}"; do
        name="${entry%% *}"; region="${entry#* }"
        printf '  Deleting Cloud Run service %s (%s)...\n' "$name" "$region"
        if gcloud run services delete "$name" \
            --project="$PROJECT" --region="$region" --quiet 2>/dev/null; then
          ok "Deleted Cloud Run service $name"
        else
          err "Failed to delete Cloud Run service $name"
        fi
      done

      # Artifact Registry
      for fullname in "${AR_DELETE[@]+"${AR_DELETE[@]}"}"; do
        local_name="${fullname##*/}"
        location=$(echo "$fullname" | cut -d/ -f4)
        printf '  Deleting Artifact Registry repo %s...\n' "$local_name"
        if gcloud artifacts repositories delete "$local_name" \
            --project="$PROJECT" --location="$location" --quiet 2>/dev/null; then
          ok "Deleted AR repo $local_name"
        else
          err "Failed to delete AR repo $local_name"
        fi
      done

      # Cloud Storage (empty buckets only)
      for bucket in "${GCS_DELETE[@]+"${GCS_DELETE[@]}"}"; do
        printf '  Checking if bucket %s is empty...\n' "$bucket"
        OBJ_COUNT=$(gcloud storage ls "gs://${bucket}" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$OBJ_COUNT" -eq 0 ]]; then
          if gcloud storage rm -r "gs://${bucket}" --quiet 2>/dev/null; then
            ok "Deleted empty bucket $bucket"
          else
            err "Failed to delete bucket $bucket"
          fi
        else
          warn "Skipping non-empty bucket $bucket (${OBJ_COUNT} objects)"
        fi
      done

    else
      info "Skipped deletion for ${PROJECT}."
    fi
  elif $KILL && [[ "$TOTAL_RES" -eq 0 ]]; then
    info "No deletable resources found in ${PROJECT}."
  fi

  # Reset arrays for next project
  VM_DELETE=(); GKE_DELETE=(); SQL_DELETE=()
  RUN_DELETE=(); AR_DELETE=(); GCS_DELETE=()

done 3< <(echo "$PROJECTS" | jq -r '.[].projectId')

printf '\n\033[1m✓ Done\033[0m\n'
