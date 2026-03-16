#!/bin/bash

# ==============================================================================
# Kueue Resource Count Check Script (Phase 1 - Burst Workloads)
#
# This script gathers counts of relevant Kueue and Kubernetes resources
# (ClusterQueues, Jobs, Pods by status and group) within a specified namespace
# and outputs the information with a provided timestamp. It's intended to be
# run as a diagnostic step during ClusterLoader2 tests.
#
# Usage: ./check_count.sh <namespace> <timestamp_string>
#
# Arguments:
#   <namespace>: The target Kubernetes namespace to check Jobs and Pods in.
#   <timestamp_string>: A string (e.g., output of 'date') to prepend to logs.
# ==============================================================================

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Exit if any command in a pipeline fails, not just the last one.
#set -euo pipefail

# --- Input Validation ---
if [[ $# -ne 2 ]]; then
    echo "Error: Invalid number of arguments." >&2
    echo "Usage: $0 <namespace> <timestamp_string>" >&2
    exit 1
fi

TARGET_NAMESPACE="$1"
LOG_TIMESTAMP="$2"

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
    echo "${LOG_TIMESTAMP} - Checking Pods: ${description}"

    # Get pod status, handle potential errors if no pods match
    pod_status=$(kubectl get pods -n "$namespace" ${selector:+-l "$selector"} --no-headers 2>/dev/null || true)

    if [[ -z "$pod_status" ]]; then
        pending_count=0
        running_count=0
        echo "${LOG_TIMESTAMP} -   No pods found matching selector '${selector:-<none>}' in namespace '${namespace}'."
    else
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
echo "${LOG_TIMESTAMP} - Starting Resource Check for Namespace: ${TARGET_NAMESPACE}"
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

# 2. Job Status (Running Count)
echo # Add a blank line
echo "${LOG_TIMESTAMP} - Checking Jobs in namespace '${TARGET_NAMESPACE}'..."
# Get all jobs first for context
ALL_JOBS=$(kubectl get job -o wide -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null || true)
if [[ -z "$ALL_JOBS" ]]; then
    RUNNING_JOB_COUNT=0
    echo "${LOG_TIMESTAMP} -   No jobs found in namespace '${TARGET_NAMESPACE}'."
else
    RUNNING_JOB_COUNT=$(echo "$ALL_JOBS" | grep -c "Running")
    # Optionally display all jobs
    # echo "${LOG_TIMESTAMP} -   All Jobs (-o wide):"
    # kubectl get job -o wide -n "$TARGET_NAMESPACE" | head -n 1
    # echo "$ALL_JOBS"
fi
printf "%s -   Running Job Count: %d\n" "$LOG_TIMESTAMP" "$RUNNING_JOB_COUNT"


# 3. Pod Status Checks (using helper function)

# Overall Pods in Namespace
get_pod_counts "$TARGET_NAMESPACE" "" "Overall Pods in Namespace"

get_pod_counts "$TARGET_NAMESPACE" "group=non-kueue-workload-tas" "Non Kueue Workload Pods (group=non-kueue-workload-tas)"

get_pod_counts "$TARGET_NAMESPACE" "group=default-workload-tas" "Default Workloads pods on default clusterqueues (group=default-workload-tas)"

get_pod_counts "$TARGET_NAMESPACE" "group=non-tas-workload-tas" "Non TAS Workload Pods on TAS enabled clusteruqueues (group=group=non-tas-workload-tas)"

get_pod_counts "$TARGET_NAMESPACE" "group=preferred-workload-tas" "Preferred TAS Workload Pods (group=preferred-workload-tas)"

get_pod_counts "$TARGET_NAMESPACE" "group=required-workload-tas" "Required TAS Workload Pods (group=required-workload-tas)"

get_pod_counts "$TARGET_NAMESPACE" "group=preferred-required-workload-tas" "Preferred Required TAS Workload Pods (group=preferred-required-workload-tas)"

get_pod_counts "$TARGET_NAMESPACE" "type=tas" "All TAS Pods (type=tas)"


echo "=================================================="
echo "${LOG_TIMESTAMP} - Resource Check Completed"
echo "=================================================="

exit 0
