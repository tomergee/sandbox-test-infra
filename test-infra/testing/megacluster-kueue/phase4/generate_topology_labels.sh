#!/bin/bash

# Script to annotate Kubernetes nodes with a multi-level hierarchy or check existing labels.
#
# Modes:
#   label: Generates and applies hierarchical labels to nodes.
#          Child counts per parent (for levels > 0) are randomized based on per-level min:max ranges.
#          Level0 (root) is unbounded. Nodes are shuffled. RANDOM is seeded.
#          Kubectl label commands are parallelized, include retries, and dry-run.
#   check: Verifies if nodes have the expected hierarchical labels. Operations are parallelized.
#          Optionally exports found labels to a CSV file. Attempts to install jq if missing.
#
# Common features: Idempotent label application (when in label mode). Parallel execution by default.

# --- Configuration & Parameters ---

# Function to display usage instructions
usage() {
    echo "Usage: $0 <operation_mode> <topology_prefix> <num_levels> ..."
    echo ""
    echo "Operation Modes:"
    echo "  label: Generate and apply hierarchical labels (parallel execution)."
    echo "    Usage: $0 label <topology_prefix> <num_levels> <level_children_ranges_str> <node_label_selector> [parallelism_level] [dry_run]"
    echo "    Example (3 levels total; L1 min:1,max:3; L2 min:2,max:5):"
    echo "      $0 label myorg.topology 3 \"1:3,2:5\" 'disktype=ssd' 5 true"
    echo "    Example (1 level total; L0 is unbounded, no ranges needed):"
    echo "      $0 label myorg.topology 1 \"\" 'disktype=ssd' 1 true"
    echo ""
    echo "  check: Check if nodes have the expected hierarchical labels (parallel execution)."
    echo "    Usage: $0 check <topology_prefix> <num_levels> <node_label_selector> [parallelism_level] [output_file_path]"
    echo "    Example: $0 check myorg.topology 3 'disktype=ssd' 4 ./label_report.csv"
    echo ""
    echo "Common Arguments for 'label' and 'check' modes:"
    echo "  <topology_prefix>        : Prefix for the topology labels (e.g., 'myorg.com/topology')."
    echo "  <num_levels>             : Number of hierarchical levels (e.g., 3 for L0, L1, L2). Must be >= 1."
    echo "  <node_label_selector>    : Kubernetes label selector to filter nodes (e.g., 'environment=production')."
    echo ""
    echo "Arguments specific to 'label' mode:"
    echo "  <level_children_ranges_str>: Comma-separated string of 'min:max' pairs for children at each level > 0."
    echo "                             Required if num_levels > 1. Number of pairs must be num_levels - 1."
    echo "                             Example for num_levels=3: \"1:3,2:4\" (L1 range, L2 range)."
    echo "                             If num_levels=1, this can be an empty string or will be ignored."
    echo "  [dry_run]                : Optional. Set to 'true' (default) to run with '--dry-run=client'."
    echo "                             Set to 'false' to apply changes to the cluster."
    echo ""
    echo "Optional Arguments for 'label' and 'check' modes:"
    echo "  [parallelism_level]      : Optional. Max number of concurrent operations. Defaults to 1."
    echo "                             Effective rolling window parallelism requires Bash 4.3+ for 'wait -n'."
    echo ""
    echo "Optional Argument specific to 'check' mode:"
    echo "  [output_file_path]       : Optional. Path to a CSV file where found labels will be exported."
}

# --- Helper Functions ---

# Function to log informational messages with a timestamp
log() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to log error messages with a timestamp to standard error
error() {
    echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Function to ensure jq is installed, attempting silent installation if needed.
ensure_jq_installed() {
    if command -v jq &> /dev/null; then
        log "jq is already installed."
        return 0 # jq is present
    fi

    log "jq not found. Attempting silent installation..."

    local installed_successfully=false
    local sudo_cmd=""

    # Check for sudo privileges if not running as root
    if [[ $EUID -ne 0 ]]; then # $EUID is 0 for root
        if command -v sudo &> /dev/null; then
            sudo_cmd="sudo"
            log "Using sudo for installation."
        else
            error "jq is not installed and sudo is not available. Please install jq manually or run as root."
            return 1 # Indicate failure to ensure jq
        fi
    fi

    # Attempt installation using common package managers
    if command -v apt-get &> /dev/null; then
        log "Attempting installation using apt-get..."
        if ${sudo_cmd} apt-get update -qq && ${sudo_cmd} apt-get install -y -qq jq; then
            installed_successfully=true
        fi
    elif command -v yum &> /dev/null; then
        log "Attempting installation using yum..."
        if ${sudo_cmd} yum install -y -q jq; then
            installed_successfully=true
        fi
    elif command -v dnf &> /dev/null; then # Newer Fedora, RHEL
        log "Attempting installation using dnf..."
        if ${sudo_cmd} dnf install -y -q jq; then
            installed_successfully=true
        fi
    elif command -v apk &> /dev/null; then # Alpine Linux
        log "Attempting installation using apk..."
        if ${sudo_cmd} apk add --no-cache jq; then
            installed_successfully=true
        fi
    elif command -v brew &> /dev/null; then # macOS Homebrew
        log "Attempting installation using Homebrew..."
        if brew install jq; then
            installed_successfully=true
        fi
    else
        error "No known package manager (apt-get, yum, dnf, apk, brew) found to install jq."
    fi

    if "$installed_successfully"; then
        log "jq installed successfully."
        return 0
    else
        error "Failed to automatically install jq. Please install it manually."
        return 1
    fi
}

# --- Function to check labels for a single node (used in 'check' mode) ---
check_single_node_labels() {
    local _node_name="$1"
    local _topology_prefix="$2"
    local _num_levels="$3"
    local _expected_keys_local=()
    local _missing_keys_for_status=()
    local _all_keys_present_for_status=true
    local _log_prefix=" (PID $$)"

    for ((_idx=0; _idx < _num_levels; _idx++)); do
        _expected_keys_local+=("${_topology_prefix}/level${_idx}")
    done

    _node_labels_json=$(kubectl get node "$_node_name" -o jsonpath='{.metadata.labels}' 2>/dev/null)
    if [ -z "$_node_labels_json" ]; then
        error "${_log_prefix} Could not retrieve labels for node ${_node_name}."
        exit 1
    fi

    local _output_lines=""
    for _expected_key in "${_expected_keys_local[@]}"; do
        _value=$(echo "$_node_labels_json" | jq -r --arg key "$_expected_key" '.[$key] // empty')
        if [ -n "$_value" ]; then
            _output_lines+="${_node_name},${_expected_key},${_value}\n"
        else
            _all_keys_present_for_status=false
            _missing_keys_for_status+=("$_expected_key")
        fi
    done

    if [ -n "$_output_lines" ]; then
        printf "%s" "$_output_lines"
    fi

    if "$_all_keys_present_for_status"; then
        log "${_log_prefix} Node '${_node_name}': OK (all ${_num_levels} expected topology label keys found)."
        exit 0
    else
        log "${_log_prefix} Node '${_node_name}': MISSING KEY(S) for status: ${_missing_keys_for_status[*]}"
        exit 1
    fi
}


# --- Main Script Start ---

OPERATION_MODE="$1"
shift # Remove the operation_mode from arguments for further parsing

# Check if kubectl command-line tool is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl command not found. Please ensure kubectl is installed and in your PATH."
    exit 1
fi


# --- Mode: label ---
if [[ "$OPERATION_MODE" == "label" ]]; then
    # --- Parameters for 'label' mode ---
    # Expected: <topology_prefix> <num_levels> <level_children_ranges_str> <node_label_selector> [parallelism_level] [dry_run]
    if [ "$#" -lt 4 ] || [ "$#" -gt 6 ]; then # 4 mandatory for label mode, 2 optional
        error "Invalid number of arguments for 'label' mode."
        usage
        exit 1
    fi
    TOPOLOGY_PREFIX="$1"
    NUM_LEVELS="$2"
    LEVEL_CHILDREN_RANGES_STR="$3" # New parameter for per-level min:max ranges
    NODE_LABEL_SELECTOR="$4"
    PARALLELISM_LEVEL="${5:-1}" # Default to 1
    DRY_RUN_INPUT="${6:-true}"   # Default to 'true'

    # --- Input Validation for 'label' mode ---
    if ! [[ "$NUM_LEVELS" =~ ^[0-9]+$ ]] || [ "$NUM_LEVELS" -lt 1 ]; then error "Error (label mode): <num_levels> must be a positive integer >= 1."; usage; exit 1; fi

    # Declare arrays for per-level min/max children counts
    declare -a MIN_CHILDREN_FOR_LEVEL=()
    declare -a MAX_CHILDREN_FOR_LEVEL=()

    if [ "$NUM_LEVELS" -gt 1 ]; then
        if [ -z "$LEVEL_CHILDREN_RANGES_STR" ]; then
            error "Error (label mode): <level_children_ranges_str> is required when NUM_LEVELS > 1."
            usage; exit 1;
        fi

        IFS=',' read -r -a ranges_array <<< "$LEVEL_CHILDREN_RANGES_STR"

        expected_pairs=$((NUM_LEVELS - 1)) # Ranges are for L1, L2, ..., L(NUM_LEVELS-1)
        if [ "${#ranges_array[@]}" -ne "$expected_pairs" ]; then
            error "Error (label mode): Expected $expected_pairs min:max pairs in <level_children_ranges_str> for $NUM_LEVELS levels (L0 is unbounded), but got ${#ranges_array[@]}."
            usage; exit 1;
        fi

        level_counter=1 # For user-friendly error messages (L1, L2, ...)
        for range_pair in "${ranges_array[@]}"; do
            min_val_str=""
            max_val_str=""
            if [[ "$range_pair" =~ ^([0-9]+):([0-9]+)$ ]]; then
                min_val_str="${BASH_REMATCH[1]}"
                max_val_str="${BASH_REMATCH[2]}"
            else
                error "Error (label mode): Invalid format for range pair '$range_pair' in <level_children_ranges_str> for L${level_counter}. Expected format 'min:max'."
                usage; exit 1;
            fi

            if ! [[ "$min_val_str" =~ ^[0-9]+$ ]] || [ "$min_val_str" -lt 1 ]; then error "Error (label mode): Min value '$min_val_str' for L${level_counter} must be a positive integer >= 1."; usage; exit 1; fi
            if ! [[ "$max_val_str" =~ ^[0-9]+$ ]] || [ "$max_val_str" -lt 1 ]; then error "Error (label mode): Max value '$max_val_str' for L${level_counter} must be a positive integer >= 1."; usage; exit 1; fi
            if [ "$min_val_str" -gt "$max_val_str" ]; then error "Error (label mode): Min value '$min_val_str' for L${level_counter} cannot be greater than Max value '$max_val_str'."; usage; exit 1; fi

            MIN_CHILDREN_FOR_LEVEL+=("$min_val_str")
            MAX_CHILDREN_FOR_LEVEL+=("$max_val_str")
            level_counter=$((level_counter + 1))
        done
    elif [ "$NUM_LEVELS" -eq 1 ] && [ -n "$LEVEL_CHILDREN_RANGES_STR" ]; then
         log "Warning (label mode): <level_children_ranges_str> ('$LEVEL_CHILDREN_RANGES_STR') provided but NUM_LEVELS is 1. Ranges will be ignored as only L0 (unbounded) exists."
    fi


    if ! [[ "$PARALLELISM_LEVEL" =~ ^[0-9]+$ ]] || [ "$PARALLELISM_LEVEL" -lt 1 ]; then error "Error (label mode): [parallelism_level] must be a positive integer >= 1."; usage; exit 1; fi
    DRY_RUN_FLAG=""
    DRY_RUN_MSG_SUFFIX="(dry-run)"
    if [[ "$DRY_RUN_INPUT" == "true" ]]; then DRY_RUN_FLAG="--dry-run=client"; elif [[ "$DRY_RUN_INPUT" == "false" ]]; then DRY_RUN_FLAG=""; DRY_RUN_MSG_SUFFIX="(LIVE RUN)"; else error "Error (label mode): [dry_run] must be 'true' or 'false'."; usage; exit 1; fi
    if [ -z "$TOPOLOGY_PREFIX" ]; then error "Error (label mode): <topology_prefix> cannot be empty."; usage; exit 1; fi
    if [ -z "$NODE_LABEL_SELECTOR" ]; then error "Error (label mode): <node_label_selector> cannot be empty."; usage; exit 1; fi

    if ! command -v shuf &> /dev/null; then error "shuf command not found. shuf (from GNU coreutils) is required for node shuffling in 'label' mode."; exit 1; fi

    SEED=$(date +%s%N); if [[ "$SEED" == *N ]] || [[ -z "$SEED" ]]; then SEED=$(date +%s); fi; RANDOM=$SEED
    log "RANDOM seeded with $SEED for 'label' mode."

    log "Starting 'label' mode: Node annotation process with per-level randomized child counts (L0 unbounded)..."
    log "Topology Prefix: ${TOPOLOGY_PREFIX}"
    log "Number of Levels: ${NUM_LEVELS}"
    if [ "$NUM_LEVELS" -gt 1 ]; then
        log "Per-Level Children Ranges (L1+): ${LEVEL_CHILDREN_RANGES_STR}"
    fi
    log "Node Label Selector: '${NODE_LABEL_SELECTOR}'"
    log "Parallelism Level: ${PARALLELISM_LEVEL}"
    log "Dry Run Mode: ${DRY_RUN_INPUT} ${DRY_RUN_MSG_SUFFIX}"

    log "Fetching nodes with label selector '${NODE_LABEL_SELECTOR}'..."
    NODE_NAMES_STRING=$(kubectl get nodes -l "${NODE_LABEL_SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')
    # # shellcheck disable=SC2207
    #INITIAL_NODE_NAMES=($NODE_NAMES_STRING)
    read -r -a INITIAL_NODE_NAMES <<< "$NODE_NAMES_STRING"
    NUM_CONCERNED_NODES=${#INITIAL_NODE_NAMES[@]}

    if [ "${NUM_CONCERNED_NODES}" -eq 0 ]; then log "No nodes found matching label selector '${NODE_LABEL_SELECTOR}'. Nothing to do. Exiting."; exit 0; fi
    log "Found ${NUM_CONCERNED_NODES} nodes: ${INITIAL_NODE_NAMES[*]}"

    log "Shuffling node list..."
    mapfile -d '' -t NODE_NAMES < <(printf "%s\0" "${INITIAL_NODE_NAMES[@]}" | shuf -z)
    log "Shuffled node list: ${NODE_NAMES[*]}"

    declare -A PARENT_MAX_CHILDREN_CONFIG
    get_parent_key_for_level() { # Function remains local to label mode
        local children_level_idx=$1; local parent_key_str
        if [ "$children_level_idx" -eq 0 ]; then parent_key_str="ROOT"; else
            local parent_path_elements_for_key=(); for ((i=0; i < children_level_idx; i++)); do parent_path_elements_for_key+=("${current_path[$i]}"); done
            local temp_key="path"; for val in "${parent_path_elements_for_key[@]}"; do temp_key+="_${val}"; done
            parent_key_str="$temp_key"; fi
        echo "$parent_key_str"; }

    log "Constructing hierarchical labels for each node..."
    declare -A LABELS_PER_NODE
    current_path=(); for ((k=0; k < NUM_LEVELS; k++)); do current_path[k]=0; done
    node_idx=0
    for node_name in "${NODE_NAMES[@]}"; do
        if [ "$node_idx" -gt 0 ]; then
            level_to_change=$((NUM_LEVELS - 1 )); while true; do
                if [ "$level_to_change" -lt 0 ]; then error "CRITICAL: Ran out of assignable hierarchical paths for ${NUM_CONCERNED_NODES} nodes."; exit 1; fi
                current_path[$level_to_change]=$((current_path[level_to_change] + 1))
                if [ "$level_to_change" -eq 0 ]; then break; fi # L0 is unbounded, path increment is enough

                # For levels > 0 (L1+), use per-level min/max ranges
                parent_key=$(get_parent_key_for_level "$level_to_change")
                if [ -z "${PARENT_MAX_CHILDREN_CONFIG[$parent_key]}" ]; then
                    # Array index for MIN/MAX_CHILDREN_FOR_LEVEL is (level_to_change - 1)
                    # because level_to_change=1 (L1) corresponds to index 0 of these arrays.
                    current_level_min=${MIN_CHILDREN_FOR_LEVEL[$((level_to_change - 1))]}
                    current_level_max=${MAX_CHILDREN_FOR_LEVEL[$((level_to_change - 1))]}
                    rand_capacity=""
                    if [ "$current_level_min" -eq "$current_level_max" ]; then
                        rand_capacity=$current_level_min
                    else
                        range_size=$((current_level_max - current_level_min + 1))
                        rand_capacity=$((current_level_min + RANDOM % range_size))
                    fi
                    PARENT_MAX_CHILDREN_CONFIG["$parent_key"]=$rand_capacity
                    log "Capacity for children of parent '${parent_key}' (items at L${level_to_change}) set to: ${rand_capacity} (range ${current_level_min}:${current_level_max})" >&2;
                fi
                max_children_for_current_parent="${PARENT_MAX_CHILDREN_CONFIG[$parent_key]}"
                if [ "${current_path[$level_to_change]}" -lt "$max_children_for_current_parent" ]; then break; else
                    current_path[$level_to_change]=0; level_to_change=$((level_to_change - 1)); fi
            done; fi
        node_specific_labels_string=""; for ((level_idx=0; level_idx < NUM_LEVELS; level_idx++)); do
            label_key="${TOPOLOGY_PREFIX}/level${level_idx}"; label_value="L${level_idx}-${current_path[$level_idx]}"
            node_specific_labels_string+="${label_key}=${label_value} "; done
        #LABELS_PER_NODE["$node_name"]=$(echo "$node_specific_labels_string" | sed 's/ *$//')
        LABELS_PER_NODE["$node_name"]="${node_specific_labels_string% }"
        log "Node '${node_name}' will be prepared with labels: ${LABELS_PER_NODE[$node_name]}"
        node_idx=$((node_idx + 1)); done

    log "Applying labels to nodes using parallel execution framework ${DRY_RUN_MSG_SUFFIX}..."
    SUCCESS_COUNT=0; FAILURE_COUNT=0
    declare -a ALL_PIDS_LAUNCHED=(); declare -A PID_TO_NODE_NAME; declare -A PID_STATUSES
    MAX_RETRIES=10; RETRY_INTERVAL_SECONDS=30

    if [ ${#LABELS_PER_NODE[@]} -eq 0 ]; then log "No labels were generated to apply."; else
        log "Executing kubectl label commands in parallel (Max ${PARALLELISM_LEVEL} jobs) ${DRY_RUN_MSG_SUFFIX}."
        can_wait_n=true; if ! ( (sleep 0.01 & wait -n) >/dev/null 2>&1 ); then can_wait_n=false; log "Warning: 'wait -n' not available (Bash 4.3+ req). Concurrency not strictly enforced as rolling window."; fi
        job_slot_counter=0
        for node_name in "${!LABELS_PER_NODE[@]}"; do
            labels_to_set="${LABELS_PER_NODE[$node_name]}"
            if "$can_wait_n" && [[ "$job_slot_counter" -ge "$PARALLELISM_LEVEL" ]]; then wait -n; job_slot_counter=$((job_slot_counter - 1)); fi
            log "Attempting to label node (parallel launch ${DRY_RUN_MSG_SUFFIX}): '${node_name}' with '${labels_to_set}'"
            ( _node_name="${node_name}"; _labels_to_set="${labels_to_set}"; _DRY_RUN_FLAG="${DRY_RUN_FLAG}"; _DRY_RUN_MSG_SUFFIX="${DRY_RUN_MSG_SUFFIX}"; _MAX_RETRIES=${MAX_RETRIES}; _RETRY_INTERVAL_SECONDS=${RETRY_INTERVAL_SECONDS}
                _retry_count=0; _labeled_successfully=false
                while [[ "$_retry_count" -lt "$_MAX_RETRIES" && "$_labeled_successfully" == "false" ]]; do
                    if [[ "$_retry_count" -gt 0 ]]; then echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - Retrying (attempt $((_retry_count + 1))/${_MAX_RETRIES}, PID $$, parallel ${_DRY_RUN_MSG_SUFFIX}): '${_node_name}'..." >&2; sleep "$_RETRY_INTERVAL_SECONDS"; fi
                    # shellcheck disable=SC2086
                    if kubectl label node "${_node_name}" ${_labels_to_set} --overwrite ${_DRY_RUN_FLAG}; then _labeled_successfully=true; fi
                    _retry_count=$((_retry_count + 1)); done
                if "$_labeled_successfully"; then exit 0; else echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - Failed to label '${_node_name}' after ${_MAX_RETRIES} attempts (PID $$, parallel ${_DRY_RUN_MSG_SUFFIX})." >&2; exit 1; fi
            ) &
            current_pid=$!; ALL_PIDS_LAUNCHED+=("$current_pid"); PID_TO_NODE_NAME["$current_pid"]="$node_name"
            if "$can_wait_n" || [[ "$PARALLELISM_LEVEL" -gt 1 ]]; then job_slot_counter=$((job_slot_counter + 1)); fi; done
        log "Waiting for all ${#ALL_PIDS_LAUNCHED[@]} launched parallel labeling jobs to complete..."
        for pid_val in "${ALL_PIDS_LAUNCHED[@]}"; do if wait "$pid_val"; then PID_STATUSES["$pid_val"]=0; else PID_STATUSES["$pid_val"]=$?; fi; done
        for pid_val in "${ALL_PIDS_LAUNCHED[@]}"; do
            node_name_for_pid="${PID_TO_NODE_NAME[$pid_val]}"; status="${PID_STATUSES[$pid_val]}"
            if [ "$status" -eq 0 ]; then log "Successfully processed '${node_name_for_pid}' (PID $pid_val) ${DRY_RUN_MSG_SUFFIX}."; SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); else error "Overall processing for '${node_name_for_pid}' (PID $pid_val) failed with $status ${DRY_RUN_MSG_SUFFIX}."; FAILURE_COUNT=$((FAILURE_COUNT + 1)); fi
        done; fi
    log "Node annotation ('label' mode) process finished."
    log "Successfully processed ${SUCCESS_COUNT} node(s) for labeling ${DRY_RUN_MSG_SUFFIX}."
    if [ "${FAILURE_COUNT}" -gt 0 ]; then error "${FAILURE_COUNT} node(s) could not be processed for labeling ${DRY_RUN_MSG_SUFFIX}."; exit 1; fi
    log "All targeted nodes processed successfully for 'label' mode ${DRY_RUN_MSG_SUFFIX}."
    exit 0


# --- Mode: check ---
elif [[ "$OPERATION_MODE" == "check" ]]; then
    # --- Parameters for 'check' mode ---
    if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then # 3 mandatory, 2 optional for check mode
        error "Invalid number of arguments for 'check' mode."
        usage
        exit 1
    fi
    TOPOLOGY_PREFIX="$1"
    NUM_LEVELS="$2"
    NODE_LABEL_SELECTOR="$3"
    PARALLELISM_LEVEL_CHECK="${4:-1}" # Default to 1
    OUTPUT_FILE_PATH="${5:-}"      # Optional output file path, defaults to empty

    # --- Input Validation for 'check' mode ---
    if ! [[ "$NUM_LEVELS" =~ ^[0-9]+$ ]] || [ "$NUM_LEVELS" -lt 1 ]; then error "Error (check mode): <num_levels> must be a positive integer >= 1."; usage; exit 1; fi
    if [ -z "$TOPOLOGY_PREFIX" ]; then error "Error (check mode): <topology_prefix> cannot be empty."; usage; exit 1; fi
    if [ -z "$NODE_LABEL_SELECTOR" ]; then error "Error (check mode): <node_label_selector> cannot be empty."; usage; exit 1; fi
    if ! [[ "$PARALLELISM_LEVEL_CHECK" =~ ^[0-9]+$ ]] || [ "$PARALLELISM_LEVEL_CHECK" -lt 1 ]; then error "Error (check mode): [parallelism_level] must be a positive integer >= 1."; usage; exit 1; fi

    if ! ensure_jq_installed; then exit 1; fi
    if ! command -v jq &> /dev/null; then error "jq is still not available after attempting installation. Exiting 'check' mode."; exit 1; fi

    log "Starting 'check' mode: Verifying hierarchical labels on nodes..."
    log "Topology Prefix: ${TOPOLOGY_PREFIX}"
    log "Number of Levels: ${NUM_LEVELS}"
    log "Node Label Selector: '${NODE_LABEL_SELECTOR}'"
    log "Parallelism Level for Check: ${PARALLELISM_LEVEL_CHECK}"
    if [ -n "$OUTPUT_FILE_PATH" ]; then log "Exporting found labels to: ${OUTPUT_FILE_PATH}"; echo "Node,LabelKey,LabelValue" > "$OUTPUT_FILE_PATH"; fi
    log "Note: Parameters like min/max children ranges, dry_run are ignored in 'check' mode."

    log "Fetching nodes with label selector '${NODE_LABEL_SELECTOR}' for checking..."
    NODE_NAMES_STRING_CHECK=$(kubectl get nodes -l "${NODE_LABEL_SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')
    # shellcheck disable=SC2207
    #NODES_TO_CHECK=($NODE_NAMES_STRING_CHECK)
    read -r -a NODES_TO_CHECK <<< "$NODE_NAMES_STRING_CHECK"
    NUM_NODES_TO_CHECK=${#NODES_TO_CHECK[@]}

    if [ "${NUM_NODES_TO_CHECK}" -eq 0 ]; then log "No nodes found matching label selector '${NODE_LABEL_SELECTOR}' to check. Exiting."; exit 0; fi
    log "Found ${NUM_NODES_TO_CHECK} nodes to check: ${NODES_TO_CHECK[*]}"
    log "Expected label keys pattern: ${TOPOLOGY_PREFIX}/level[0-$((NUM_LEVELS - 1))]"

    correctly_labeled_count=0; nodes_with_missing_labels=0
    declare -a CHECK_PIDS=(); declare -A CHECK_PID_STATUSES
    TMP_OUTPUT_DIR=""
    if [ -n "$OUTPUT_FILE_PATH" ]; then TMP_OUTPUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/check_labels_output.XXXXXX"); log "Temporary output directory for parallel checks: ${TMP_OUTPUT_DIR}"; fi

    export -f log; export -f error; export -f check_single_node_labels

    log "Checking node labels using parallel execution framework (Max ${PARALLELISM_LEVEL_CHECK} jobs)."
    can_wait_n_check=true; if ! ( (sleep 0.01 & wait -n) >/dev/null 2>&1 ); then can_wait_n_check=false; log "Warning: 'wait -n' not available (Bash 4.3+ req). Concurrency not strictly enforced as rolling window for check mode."; fi
    job_slot_counter_check=0
    for node_name in "${NODES_TO_CHECK[@]}"; do
        if "$can_wait_n_check" && [[ "$job_slot_counter_check" -ge "$PARALLELISM_LEVEL_CHECK" ]]; then wait -n; job_slot_counter_check=$((job_slot_counter_check - 1)); fi
        if [ -n "$OUTPUT_FILE_PATH" ]; then
            ( check_single_node_labels "$node_name" "$TOPOLOGY_PREFIX" "$NUM_LEVELS" > "${TMP_OUTPUT_DIR}/${node_name}_${BASHPID}.tmp" ) &
        else
            ( check_single_node_labels "$node_name" "$TOPOLOGY_PREFIX" "$NUM_LEVELS" ) &
        fi
        current_pid_check=$!; CHECK_PIDS+=("$current_pid_check")
        if "$can_wait_n_check" || [[ "$PARALLELISM_LEVEL_CHECK" -gt 1 ]]; then job_slot_counter_check=$((job_slot_counter_check + 1)); fi; done

    log "Waiting for all ${#CHECK_PIDS[@]} launched parallel check jobs to complete..."
    for pid_val_check in "${CHECK_PIDS[@]}"; do if wait "$pid_val_check"; then CHECK_PID_STATUSES["$pid_val_check"]=0; else CHECK_PID_STATUSES["$pid_val_check"]=1; fi; done
    for pid_val_check in "${CHECK_PIDS[@]}"; do
        status_check="${CHECK_PID_STATUSES[$pid_val_check]}"
        if [ "$status_check" -eq 0 ]; then correctly_labeled_count=$((correctly_labeled_count + 1)); else nodes_with_missing_labels=$((nodes_with_missing_labels + 1)); fi; done

    if [ -n "$OUTPUT_FILE_PATH" ] && [ -d "$TMP_OUTPUT_DIR" ]; then
        log "Consolidating label export data from temporary files..."
        find "$TMP_OUTPUT_DIR" -type f -name "*.tmp" -print0 | xargs -0 -r cat >> "$OUTPUT_FILE_PATH"
        log "Cleaning up temporary output directory: ${TMP_OUTPUT_DIR}"; rm -rf "$TMP_OUTPUT_DIR"; fi

    log "Label check finished."
    log "Summary: ${correctly_labeled_count} out of ${NUM_NODES_TO_CHECK} node(s) have all expected topology label keys."
    if [ -n "$OUTPUT_FILE_PATH" ]; then log "Found labels have been exported to: ${OUTPUT_FILE_PATH}"; fi
    if [ "$nodes_with_missing_labels" -gt 0 ]; then error "${nodes_with_missing_labels} node(s) are missing one or more expected topology label keys."; exit 1; else log "All checked nodes have all expected topology label keys."; exit 0; fi

# --- Invalid Mode ---
else
    error "Invalid operation_mode: '${OPERATION_MODE}'."
    usage
    exit 1
fi
