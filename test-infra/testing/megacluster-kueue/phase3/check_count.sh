#!/bin/bash

# ==============================================================================
# Kueue Resource Count Check Script (Phase 3 - Fair Sharing)
#
# This script gathers counts of relevant Kueue and Kubernetes resources
# (ClusterQueues, Jobs, Pods by status and group) within two specified
# namespaces (Team Alpha and Team Beta) and outputs the information with a
# provided timestamp. It's intended to be run as a diagnostic step during
# ClusterLoader2 tests for the fair sharing phase.
#
# Usage: ./check_count.sh <namespace_alpha> <namespace_beta> <timestamp_string>
#
# Arguments:
#   <namespace_alpha>: The target namespace for Team Alpha workloads.
#   <namespace_beta>:  The target namespace for Team Beta workloads.
#   <timestamp_string>: A string (e.g., output of 'date') to prepend to logs.
# ==============================================================================

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Exit if any command in a pipeline fails, not just the last one.
#set -euo pipefail

# --- Input Validation ---
if [[ $# -ne 3 ]]; then
    echo "Error: Invalid number of arguments." >&2
    echo "Usage: $0 <namespace_alpha> <namespace_beta> <timestamp_string>" >&2
    exit 1
fi

NAMESPACE_ALPHA="$1"
NAMESPACE_BETA="$2"
LOG_TIMESTAMP="$3"

# --- Namespace Ordering Check ---
# Ensure Alpha is Alpha and Beta is Beta, swap if necessary based on simple check.
# This assumes namespaces contain 'alpha' or 'beta' in their names.
if [[ "$NAMESPACE_ALPHA" == *beta* && "$NAMESPACE_BETA" == *alpha* ]]; then
  echo "${LOG_TIMESTAMP} - Info: Swapping alpha and beta namespace arguments based on name."
  temp="$NAMESPACE_ALPHA"
  NAMESPACE_ALPHA="$NAMESPACE_BETA"
  NAMESPACE_BETA="$temp"
elif [[ "$NAMESPACE_ALPHA" == *beta* || "$NAMESPACE_BETA" == *alpha* ]]; then
   echo "Warning: Namespace arguments might be in the wrong order but couldn't reliably swap." >&2
   echo "  Proceeding with NAMESPACE_ALPHA=$NAMESPACE_ALPHA, NAMESPACE_BETA=$NAMESPACE_BETA" >&2
fi


# --- Helper Functions ---
# Function to get pod counts (Pending, Running) for a given selector
get_pod_counts() {
    local namespace="$1"
    local selector="$2"
    local description="$3"
    local pod_status
    local pending_count
    local running_count

    echo # Add a blank line for readability
    echo "${LOG_TIMESTAMP} - Checking Pods: ${description} in namespace '${namespace}'"

    # Get pod status, handle potential errors if no pods match
    pod_status=$(kubectl get pods -n "$namespace" ${selector:+-l "$selector"} --no-headers 2>/dev/null || true)

    if [[ -z "$pod_status" ]]; then
        pending_count=0
        running_count=0
        echo "${LOG_TIMESTAMP} -   No pods found matching selector '${selector:-<none>}'."
    else
        # Count based on lines containing the status, robust against extra spaces/columns
        pending_count=$(echo "$pod_status" | grep -c "Pending")
        running_count=$(echo "$pod_status" | grep -c "Running")
        # Optionally display the raw status for debugging
        # echo "${LOG_TIMESTAMP} -   Raw Status:"
        # echo "$pod_status" | sed 's/^/    /' # Indent output
    fi

    printf "%s -   Counts: Pending=%d, Running=%d\n" "$LOG_TIMESTAMP" "$pending_count" "$running_count"
}

# --- Resource Checks ---

echo "=================================================="
echo "${LOG_TIMESTAMP} - Starting Resource Check (Phase 3 - Fair Sharing)"
echo "${LOG_TIMESTAMP} -   Namespace Alpha: ${NAMESPACE_ALPHA}"
echo "${LOG_TIMESTAMP} -   Namespace Beta:  ${NAMESPACE_BETA}"
echo "=================================================="

# 1. ClusterQueue Status
echo # Add a blank line
echo "${LOG_TIMESTAMP} - Checking ClusterQueues..."
CLUSTER_QUEUES=$(kubectl get clusterqueue -o wide --no-headers 2>/dev/null || echo "No ClusterQueues found or error fetching.")
echo "${LOG_TIMESTAMP} - ClusterQueue Status (-o wide):"
if [[ "$CLUSTER_QUEUES" == "No ClusterQueues found or error fetching." ]]; then
    echo "$CLUSTER_QUEUES"
else
    # Print header and then the queues
    kubectl get clusterqueue -o wide | head -n 1
    echo "$CLUSTER_QUEUES"
fi

# 2. Job Status (Running Count per Namespace)
echo # Add a blank line
echo "${LOG_TIMESTAMP} - Checking Jobs..."
# Alpha Jobs
ALL_JOBS_ALPHA=$(kubectl get job -o wide -n "$NAMESPACE_ALPHA" --no-headers 2>/dev/null || true)
if [[ -z "$ALL_JOBS_ALPHA" ]]; then
    RUNNING_JOB_COUNT_ALPHA=0
    echo "${LOG_TIMESTAMP} -   No jobs found in namespace '${NAMESPACE_ALPHA}'."
else
    RUNNING_JOB_COUNT_ALPHA=$(echo "$ALL_JOBS_ALPHA" | grep -c "Running")
fi
printf "%s -   Namespace Alpha Running Job Count: %d\n" "$LOG_TIMESTAMP" "$RUNNING_JOB_COUNT_ALPHA"

# Beta Jobs
ALL_JOBS_BETA=$(kubectl get job -o wide -n "$NAMESPACE_BETA" --no-headers 2>/dev/null || true)
if [[ -z "$ALL_JOBS_BETA" ]]; then
    RUNNING_JOB_COUNT_BETA=0
    echo "${LOG_TIMESTAMP} -   No jobs found in namespace '${NAMESPACE_BETA}'."
else
    RUNNING_JOB_COUNT_BETA=$(echo "$ALL_JOBS_BETA" | grep -c "Running")
fi
printf "%s -   Namespace Beta Running Job Count: %d\n" "$LOG_TIMESTAMP" "$RUNNING_JOB_COUNT_BETA"


# 3. Pod Status Checks (using helper function)

# Overall Pods per Namespace
get_pod_counts "$NAMESPACE_ALPHA" "" "Overall Pods (Alpha)"
get_pod_counts "$NAMESPACE_BETA" "" "Overall Pods (Beta)"

# Pods for Part 1 Workloads (if applicable)
get_pod_counts "$NAMESPACE_ALPHA" "group=alpha-team-low" "Alpha Team Low Prio Pods (Part 1)"
get_pod_counts "$NAMESPACE_ALPHA" "group=alpha-team-medium" "Alpha Team Medium Prio Pods (Part 1)"
get_pod_counts "$NAMESPACE_BETA" "group=beta-team-high" "Beta Team High Prio Pods (Part 1)"

# Pods for Part 2 Workloads
get_pod_counts "$NAMESPACE_ALPHA" "group=alpha-team-large-job" "Alpha Team Large Job Pods (Part 2)"
get_pod_counts "$NAMESPACE_ALPHA" "group=alpha-team-medium-job" "Alpha Team Medium Job Pods (Part 2)"
get_pod_counts "$NAMESPACE_ALPHA" "group=alpha-team-small-job" "Alpha Team Small Job Pods (Part 2)"
get_pod_counts "$NAMESPACE_BETA" "group=beta-team-small-job" "Beta Team Small Job Pods (Part 2)"
get_pod_counts "$NAMESPACE_BETA" "group=beta-team-medium-job" "Beta Team Medium Job Pods (Part 2)"
get_pod_counts "$NAMESPACE_BETA" "group=beta-team-large-job" "Beta Team Large Job Pods (Part 2)"


echo "=================================================="
echo "${LOG_TIMESTAMP} - Resource Check Completed (Phase 3)"
echo "=================================================="

exit 0
