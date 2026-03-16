#!/bin/bash

# ####################################################################################
#
# A script to calculate the character count of workload object definitions.
#
# It follows this specific workflow:
# 1. Lists workload objects.
# 2. Extracts the kind and name of each workload.
# 3. For each workload, fetches its full JSON definition.
# 4. Compacts the JSON (removing non-essential whitespace) and counts the characters.
# 5. Reports the name and size for every workload.
# 6. Reports which workload has the largest size.
#
# Usage:
#   ./find_largest_workload.sh [namespace]
#
# If no namespace is provided, it will use the active/default namespace.
#
# Requirements:
#   - kubectl: The Kubernetes command-line tool.
#   - jq: A command-line JSON processor used here to compact the JSON output.
#
# ####################################################################################

# --- 1. SETUP & INPUT ---

# Set the namespace from the first argument, or use the current default if not provided
NAMESPACE_FLAG=""
if [ -n "$1" ]; then
  NAMESPACE="$1"
  NAMESPACE_FLAG="--namespace=$NAMESPACE"
  echo "Using namespace: $NAMESPACE"
else
  NAMESPACE=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null || echo "default")
  NAMESPACE_FLAG="--namespace=$NAMESPACE"
  echo "No namespace provided, using current/default namespace: $NAMESPACE"
fi

# Check for jq, which is required for reliable JSON processing
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to run this script."
    echo "e.g., 'sudo apt-get install jq' or 'brew install jq'"
    exit 1
fi

echo "---"

# --- 2. GET WORKLOADS & EXTRACT NAMES ---

# Note: "kubectl get workload" is not a standard command. We explicitly get common
# workload types and extract their kind and name for processing.
# We use custom-columns to get a clean, parsable list.
WORKLOAD_LIST=$(kubectl get workloads,deployments,statefulsets,daemonsets,replicasets,jobs,jobsets,lws,cronjobs "$NAMESPACE_FLAG" -o custom-columns=KIND:.kind,NAME:.metadata.name --no-headers=true 2>/dev/null)

if [ -z "$WORKLOAD_LIST" ]; then
  echo "No workload objects found in namespace '$NAMESPACE'."
  exit 0
fi

# --- 3. PROCESS EACH WORKLOAD ---

max_size=0
max_name=""
all_results=""

# Use a process substitution to read each line of the workload list
while read -r kind name; do
  # Skip empty lines that might result from the kubectl command
  if [ -z "$kind" ] || [ -z "$name" ]; then
    continue
  fi

  workload_fullname="$kind/$name"
  echo "Processing: $workload_fullname"

  # 3. For each workload, get its full JSON definition
  json_output=$(kubectl get "$kind" "$name" "$NAMESPACE_FLAG" -o json)

  # 4. Remove white spaces (by compacting the JSON)
  # 5. Count characters
  #    jq -c removes newlines and indentation. wc -c counts the bytes/characters.
  #    tr -d ' ' removes any remaining spaces (belt-and-suspenders).
  size=$(echo "$json_output" | jq -c . | wc -c | tr -d ' ')

  # Store the result for the final report
  all_results="${all_results}${workload_fullname},${size}\n"

  # Check for the maximum size
  if (( size > max_size )); then
    max_size=$size
    max_name=$workload_fullname
  fi

done <<< "$WORKLOAD_LIST"

# --- 6. REPORT RESULTS ---

echo "---"
echo "Report: Workload Object Sizes in Namespace '$NAMESPACE'"
echo "--------------------------------------------------"
printf "%-40s | %s\n" "WORKLOAD" "SIZE (characters)"
echo "--------------------------------------------------"

# Print all results
echo -e "$all_results" | while IFS=, read -r workload_name workload_size; do
  printf "%-40s | %s\n" "$workload_name" "$workload_size"
done

echo "--------------------------------------------------"
echo
echo "Analysis Complete."
if [ -n "$max_name" ]; then
  echo "Largest workload object is '$max_name' with $max_size characters."
else
  echo "Could not determine the largest workload."
fi