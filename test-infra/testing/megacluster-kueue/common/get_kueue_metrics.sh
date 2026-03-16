#!/bin/bash
#
# A simple script to get the current CPU and Memory usage of
# all kueue-controller-manager pods in a cluster.
#
# Usage:
#   ./metrics.sh
#

# --- Configuration ---
NAMESPACE="kueue-system"
POD_NAME_IDENTIFIER="kueue-controller-manager"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl command not found. Please ensure it is installed and in your PATH." >&2
    exit 1
fi

echo "Fetching current metrics for '$POD_NAME_IDENTIFIER' pods in namespace '$NAMESPACE'..."

# Get a single, consistent timestamp for this batch of metrics.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S%Z")

# Get the metrics data
output=$(kubectl top pod -n "$NAMESPACE" --no-headers=true 2>/dev/null | grep "$POD_NAME_IDENTIFIER" || true)

# Check if any pods were found
if [ -z "$output" ]; then
  echo "No '$POD_NAME_IDENTIFIER' pods found or Kubernetes Metrics Server is not available." >&2
  exit 0
fi

# Print header and formatted output
echo "pod_name,timestamp,cpu_usage,memory_usage"
echo "$output" | while read -r pod_name cpu_usage memory_usage; do
  printf "%s,%s,%s,%s\n" "$pod_name" "$TIMESTAMP" "$cpu_usage" "$memory_usage"
done
