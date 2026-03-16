#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Script Configuration & Helper Functions ---

# A function to log messages
log() {
  echo "[INFO] $1"
}

# A function to log errors and exit
fail() {
  echo "[ERROR] $1" >&2
  exit 1
}

# Checks if a pattern exists. If not, fails the script.
# Usage: assert_exists "file" "pattern" "Failure message"
assert_exists() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -q "$pattern" "$file"; then
    fail "$message. Pattern not found: '$pattern'"
  fi
}

# --- Change Functions ---

# Each function encapsulates one logical change from the diff.
# They are designed to be idempotent.

apply_pprof_address_setting() {
  local file="$1"
  log "Applying: Uncomment pprofBindAddress"
  if grep -q "^ *pprofBindAddress: :8083" "$file"; then
    log "Already applied."
    return
  fi
  assert_exists "$file" "^ *#pprofBindAddress: :8083" "Context for pprofBindAddress (commented line with port 8083)"
  sed -i 's/^\( *\)#\(pprofBindAddress: :8083\)/\1\2/' "$file"
  assert_exists "$file" "^ *pprofBindAddress: :8083" "Failed to uncomment pprofBindAddress"
}

update_group_concurrency() {
  local file="$1"
  log "Applying: Update groupKindConcurrency values"
  if grep -q "Job.batch: 500" "$file"; then
    log "Already applied."
    return
  fi
  assert_exists "$file" "      groupKindConcurrency:" "Context for groupKindConcurrency"
  # This replaces each line individually for robustness, preserving indentation.
  sed -i 's/^\( *\)Job.batch: 5/\1Job.batch: 500/' "$file"
  sed -i 's/^\( *\)Pod: 5/\1Pod: 500/' "$file"
  sed -i 's/^\( *\)Workload.kueue.x-k8s.io: 5/\1Workload.kueue.x-k8s.io: 500/' "$file"
  sed -i 's/^\( *\)LocalQueue.kueue.x-k8s.io: 1/\1LocalQueue.kueue.x-k8s.io: 500/' "$file"
  sed -i 's/^\( *\)Cohort.kueue.x-k8s.io: 1/\1Cohort.kueue.x-k8s.io: 500/' "$file"
  sed -i 's/^\( *\)ClusterQueue.kueue.x-k8s.io: 1/\1ClusterQueue.kueue.x-k8s.io: 500/' "$file"
  sed -i 's/^\( *\)ResourceFlavor.kueue.x-k8s.io: 1/\1ResourceFlavor.kueue.x-k8s.io: 500/' "$file"
}

update_client_connection() {
  local file="$1"
  log "Applying: Update clientConnection"
  if grep -q "qps: 1000" "$file"; then
    log "Already applied."
    return
  fi
  assert_exists "$file" "      qps: 50" "qps setting"
  assert_exists "$file" "      burst: 100" "burst setting"
  sed -i 's/^\( *\)qps: 50/\1qps: 1000/' "$file"
  sed -i 's/^\( *\)burst: 100/\1burst: 1000/' "$file"
}

apply_managed_jobs_namespace_selector_setting() {
  local file="$1"
  log "Applying: Update managedJobsNamespaceSelector"
  if grep -q "kueue-managed: \"true\"" "$file"; then
    log "Already applied."
    return
  fi
  assert_exists "$file" "#managedJobsNamespaceSelector:" "Context for namespace selector"
  sed -i '/^ *#managedJobsNamespaceSelector:/,/^ *#      values: \[ kube-system, kueue-system \]/c\
    managedJobsNamespaceSelector:\
      matchLabels:\
        kueue-managed: "true"' "$file"
}

uncomment_integrations() {
  local file="$1"
  local lws_present="$2"
  log "Applying: Uncomment integrations (pod, deployment, etc.)"
  sed -i 's/^ *#  - "pod"$/      - "pod"/' "$file"
  sed -i 's/^ *#  - "deployment".*$/      - "deployment" # requires enabling pod integration/' "$file"

  if [ "$lws_present" = true ]; then
      log "Found leaderworkerset integration, uncommenting..."
      sed -i 's/^ *#  - "leaderworkerset.*$/      - "leaderworkerset.x-k8s.io\/leaderworkerset" # requires enabling pod integration/' "$file"
  else
      log "Leaderworkerset integration not found in original manifest, skipping."
  fi
}

apply_fair_sharing_setting() {
    local file="$1"
    log "Applying: Enable fairSharing"
    sed -i 's/^ *#fairSharing:/    fairSharing:/' "$file"
    sed -i 's/^\( *\)#  enable: true/\1  enable: true/' "$file"
    sed -i 's/^\( *\)#  preemptionStrategies:.*/\1  preemptionStrategies: [LessThanOrEqualToFinalShare, LessThanInitialShare]/' "$file"
}

apply_replicas_setting() {
  local file="$1"
  local replicas="$2"
  log "Applying: Update manager replica count to ${replicas}"
  sed -i "/name: kueue-controller-manager/,/template:/ s/^\( *\)replicas: [0-9]\+/\1replicas: ${replicas}/" "$file"
  assert_exists "$file" "replicas: ${replicas}" "Failed to update replicas"
}

apply_tas_feature_gate_setting() {
  local file="$1"
  log "Applying: TAS feature gate setting"
  if grep -q "TopologyAwareScheduling=true" "$file"; then
    log "Already applied."
    return
  fi
  assert_exists "$file" "zap-log-level=2" "Context for feature gates"
  sed -i '/--zap-log-level=2/a \        - --feature-gates=TopologyAwareScheduling=true\n        #- --feature-gates=LocalQueueMetrics=true' "$file"
}

apply_probe_settings() {
  local file="$1"
  log "Applying: Update liveness and readiness probes"
  sed -i '/livenessProbe:/,/readinessProbe:/ s/^\( *\)initialDelaySeconds: 15/\1initialDelaySeconds: 300/' "$file"
  sed -i '/livenessProbe:/,/readinessProbe:/ s/^\( *\)periodSeconds: 20/\1periodSeconds: 120/' "$file"
  sed -i '/readinessProbe:/,/resources:/ s/^\( *\)initialDelaySeconds: 5/\1initialDelaySeconds: 300/' "$file"
  sed -i '/readinessProbe:/,/resources:/ s/^\( *\)periodSeconds: 10/\1periodSeconds: 120/' "$file"
}

update_cpu() {
  local file="$1"
  local cpu="$2"
  log "Applying: Update resource CPU to ${cpu}"
  sed -i "/limits:/,/requests:/ s/^\( *\)cpu: .*/\1cpu: ${cpu}/" "$file"
  sed -i "/requests:/,/securityContext:/ s/^\( *\)cpu: .*/\1cpu: ${cpu}/" "$file"
}

update_memory() {
  local file="$1"
  local memory="$2"
  log "Applying: Update resource Memory to ${memory}"
  sed -i "/limits:/,/requests:/ s/^\( *\)memory: .*/\1memory: ${memory}/" "$file"
  sed -i "/requests:/,/securityContext:/ s/^\( *\)memory: .*/\1memory: ${memory}/" "$file"
}


# --- Final Validation ---

validate_final_state() {
  local file="$1"
  local apply_tas_config="$2"
  local apply_fair_sharing="$3"
  local apply_integrations="$4"
  local replicas="$5"
  local cpu="$6"
  local memory="$7"
  local apply_high_throughput="$8"
  local lws_present="$9"

  log "--- Running Final Validation ---"
  local all_passed=true

  # Base patterns that should always exist
  local patterns=(
    "pprofBindAddress: :8083"
    'kueue-managed: "true"'
  )

  # Conditionally add patterns based on flags
  if [ "$apply_high_throughput" = true ]; then
    patterns+=( "Job.batch: 500" "qps: 1000" "burst: 1000" )
  else
    patterns+=( "Job.batch: 5" "qps: 50" "burst: 100" )
  fi

  if [ "$apply_tas_config" = true ]; then
    patterns+=('TopologyAwareScheduling=true')
  fi
  if [ "$apply_fair_sharing" = true ]; then
    patterns+=('    fairSharing:' '      preemptionStrategies: \[LessThanOrEqualToFinalShare, LessThanInitialShare\]')
  fi
  if [ "$apply_integrations" = true ]; then
    patterns+=('      - "pod"' '      - "deployment"')
    if [ "$lws_present" = true ]; then
        patterns+=('      - "leaderworkerset')
    fi
  fi

  # Validate replicas
  local expected_replicas="${replicas:-1}"
  patterns+=("replicas: ${expected_replicas}")
  if [ -n "$cpu" ]; then
    if [[ $(grep -c "cpu: ${cpu}" "$file") -lt 2 ]]; then
        echo "[FAIL] Validation failed: Expected 2 instances of 'cpu: ${cpu}'"
        all_passed=false
    else
        echo "[PASS] Found custom cpu: ${cpu}"
    fi
  else
    patterns+=('cpu: 500m')
  fi

  if [ -n "$memory" ]; then
    if [[ $(grep -c "memory: ${memory}" "$file") -lt 2 ]]; then
        echo "[FAIL] Validation failed: Expected 2 instances of 'memory: ${memory}'"
        all_passed=false
    else
        echo "[PASS] Found custom memory: ${memory}"
    fi
  else
    if [[ $(grep -c "memory: 512Mi" "$file") -lt 2 ]]; then
        echo "[FAIL] Validation failed: Expected 2 instances of default 'memory: 512Mi'"
        all_passed=false
    else
        echo "[PASS] Found default memory"
    fi
  fi

  for pattern in "${patterns[@]}"; do
    if ! grep -q "$pattern" "$file"; then
      echo "[FAIL] Validation failed: Pattern not found: '$pattern'"
      all_passed=false
    else
      echo "[PASS] Found: '$pattern'"
    fi
  done

  if [ "$all_passed" = "false" ]; then
    fail "One or more final validation checks failed."
  fi
  log "--- Final Validation Passed ---"
}


# --- Main Execution ---

usage() {
    echo "Usage: $0 [options] <input_yaml_path> <output_yaml_path>"
    echo "Options:"
    echo "  --enable-tas <true|false>       Enable TAS feature gate in Kueue config (default: true)"
    echo "  --fair-sharing <true|false>     Enable fair sharing (default: true)"
    echo "  --integrations <true|false>     Enable extra integrations (default: true)"
    echo "  --high-throughput <true|false>  Bump concurrency and client connection (default: false)"
    echo "  --replicas <count>              Override manager replica count (from manifest)."
    echo "  --cpu <value>                   Override manager CPU request/limit (from manifest)."
    echo "  --memory <value>                Override manager memory request/limit (from manifest)."
    exit 1
}

main() {
  # Default flag values
  ENABLE_TAS=true
  WITH_FAIR_SHARING=true
  WITH_INTEGRATIONS=true
  WITH_HIGH_THROUGHPUT=false
  REPLICAS=""
  CPU=""
  MEMORY=""

  # Parse flags
  ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable-tas) ENABLE_TAS="$2"; shift 2 ;;
      --fair-sharing) WITH_FAIR_SHARING="$2"; shift 2 ;;
      --integrations) WITH_INTEGRATIONS="$2"; shift 2 ;;
      --high-throughput) WITH_HIGH_THROUGHPUT="$2"; shift 2 ;;
      --replicas) REPLICAS="$2"; shift 2 ;;
      --cpu) CPU="$2"; shift 2 ;;
      --memory) MEMORY="$2"; shift 2 ;;
      -*) echo "Unknown option: $1"; usage ;;
      *) ARGS+=("$1"); shift ;;
    esac
  done

  # Restore positional arguments
  set -- "${ARGS[@]}"

  if [ "$#" -ne 2 ]; then
    usage
  fi

  local input_file="$1"
  local output_file="$2"

  if [ ! -f "$input_file" ]; then
    fail "Input file not found at '$input_file'"
  fi

  # Create a temporary working copy
  cp "$input_file" "$output_file"
  log "Created working copy at '$output_file'"

  # --- Pre-flight checks on the manifest content ---
  local leaderworkerset_present=false
  if grep -q '#  - "leaderworkerset.x-k8s.io/leaderworkerset"' "$output_file"; then
    leaderworkerset_present=true
  fi
  # --- End of Pre-flight checks ---

  # Apply all changes in order
  apply_pprof_address_setting "$output_file"

  if [ "$WITH_HIGH_THROUGHPUT" = true ]; then
    log "Applying high throughput settings."
    update_group_concurrency "$output_file"
    update_client_connection "$output_file"
  else
    log "Skipping high throughput settings as per flag."
  fi

  apply_managed_jobs_namespace_selector_setting "$output_file"

  if [ "$WITH_INTEGRATIONS" = true ]; then
    uncomment_integrations "$output_file" "$leaderworkerset_present"
  else
    log "Skipping integrations as per flag."
  fi

  if [ "$WITH_FAIR_SHARING" = true ]; then
    apply_fair_sharing_setting "$output_file"
  else
    log "Skipping fair sharing as per flag."
  fi

  if [ -n "$REPLICAS" ]; then
    apply_replicas_setting "$output_file" "$REPLICAS"
  else
    log "Keeping default replica count from manifest."
  fi

  if [ "$ENABLE_TAS" = true ]; then
    apply_tas_feature_gate_setting "$output_file"
  else
    log "Skipping TAS feature gate setting as per flag."
  fi

  apply_probe_settings "$output_file"

  if [ -n "$CPU" ]; then
    update_cpu "$output_file" "$CPU"
  fi
  if [ -n "$MEMORY" ]; then
    update_memory "$output_file" "$MEMORY"
  fi
  if [ -z "$CPU" ] && [ -z "$MEMORY" ]; then
      log "Keeping default resource settings from manifest."
  fi

  # Run final validation
  validate_final_state "$output_file" "$ENABLE_TAS" "$WITH_FAIR_SHARING" "$WITH_INTEGRATIONS" "$REPLICAS" "$CPU" "$MEMORY" "$WITH_HIGH_THROUGHPUT" "$leaderworkerset_present"

  log "All changes applied successfully to '$output_file'"
}

# Run the main function with all script arguments
main "$@"