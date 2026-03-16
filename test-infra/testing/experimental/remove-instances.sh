#!/bin/bash
# Script used as a part of ClusterLoader2 chaos testing
#
# As a part of extended performance testing for big clsuters we are checking if
# control plane of a cluster can survice removal of signicifant number of nodes
# during e2e performance testing. Currently, it's not supported in
# ClusterLoader2 (https://github.com/kubernetes/perf-tests) to remove a batch of
# instances (like ~1k instances). Instead, we are using CLI solution specific
# for GCP.
#
# It's assumed that it's run as a part of exec measurement inside ClusterLoader2
# run from kubetest. It means that there are some assumption about set
# environment variables:
#  * ZONE is set (for regional cluster, it matches one of zones)
#  * For regional cluster, REGION is set
#  * PROJECT is set
#  * CLUSTER_NAME is set
#
# Also, it's assumed that gcloud is configured.
#
# Usage:
#   ./remove_gke_instances.sh [instance_count] [filter_regex] [positive|negative]
#
# Parameters:
#   [instance_count]: (Optional) The total number of instances to remove. Defaults to 1000.
#   [filter_regex]:   (Optional) A regex to filter node pool names. Defaults to 'default'.
#   [positive|negative]: (Optional) Sets the filter mode.
#                        'positive' (default): affects node pools matching the regex.
#                        'negative': affects node pools NOT matching the regex.
#
set -eux

# --- Argument Parsing ---
pending_instances_to_remove="${1:-1000}"
group_name_filter="${2:-default}"
match_mode="${3:-positive}"

# Validate the match_mode parameter.
if [[ "${match_mode}" != "positive" && "${match_mode}" != "negative" ]]; then
  echo "[ERROR] Invalid match mode: '${match_mode}'. The third parameter must be 'positive' or 'negative'." >&2
  exit 1
fi

echo "--- Script Start ---"
echo "[INFO] Goal: Remove a total of ${pending_instances_to_remove} instances."
echo "[INFO] Node Pool filter provided: '${group_name_filter}'"
echo "[INFO] Match mode set to: '${match_mode}'"


# Set the gcloud filter operator based on the match mode.
filter_operator="~"
if [[ "${match_mode}" == "negative" ]]; then
  filter_operator="!~"
fi

echo "[INFO] Using gcloud filter operator: '${filter_operator}'"


# --- Location Logic ---
if [[ -v REGION ]]; then
  location="--region=${REGION}"
  echo "[INFO] Using REGION: ${REGION}"
elif [[ -v ZONE ]]; then
  location="--zone=${ZONE}"
  echo "[INFO] Using ZONE: ${ZONE}"
else
  echo "[ERROR] Missing required REGION or ZONE variables"
  exit 1
fi

full_gcloud_filter="name${filter_operator}'${group_name_filter}'"
echo "[INFO] Querying for node pools with filter: ${full_gcloud_filter}"
echo "--------------------"

# --- Main Loop ---
for instance_group_url in $(gcloud container node-pools list --project "${PROJECT}" --cluster "${CLUSTER_NAME}" "${location}" --format 'value[delimiter=" "](instanceGroupUrls)' --filter="${full_gcloud_filter}"); do
  IFS='/' read -r zone name <<< "$(echo -n "${instance_group_url}" | cut -d/ -f9,11)"

  echo "[INFO] Found matching instance group: '${name}' in zone '${zone}'"

  if [[ $pending_instances_to_remove -le 0 ]]; then
    echo "[INFO] All requested instances have been removed. Skipping remaining groups."
    break
  fi

  target_size="$(gcloud compute instance-groups managed describe "${name}" --zone "${zone}" --project "${PROJECT}" --format 'value(targetSize)')"
  echo "[INFO]   -> Current size: ${target_size}. Instances still to remove: ${pending_instances_to_remove}."

  instances_to_remove_from_this_group=0
  if [[ $target_size -ge $pending_instances_to_remove ]]; then
    new_target_size="$((target_size - pending_instances_to_remove))"
    instances_to_remove_from_this_group=$pending_instances_to_remove
    pending_instances_to_remove=0
  else
    new_target_size=0
    instances_to_remove_from_this_group=$target_size
    pending_instances_to_remove="$((pending_instances_to_remove - target_size))"
  fi

  echo "[INFO]   -> Will remove ${instances_to_remove_from_this_group} instance(s) from this group."
  echo "[INFO]   -> Calculated new size: ${new_target_size}"

  if [[ $target_size -ne $new_target_size ]]; then
    echo "[INFO]   -> EXECUTING: Resizing '${name}' from ${target_size} to ${new_target_size}..."
    gcloud compute instance-groups managed resize "${name}" --project "${PROJECT}" --zone="${zone}" --size "${new_target_size}"
    echo "[INFO]   -> Resize command sent for '${name}'."
  else
    echo "[INFO]   -> No size change needed for '${name}'."
  fi
  echo "--------------------"
done

# --- Final Check ---
echo "--- Script End ---"
if [[ $pending_instances_to_remove -le 0 ]]; then
  echo "[SUCCESS] Successfully removed all requested instances."
else
  echo "[ERROR] Failed to remove all requested instances. Still pending: ${pending_instances_to_remove}"
  exit 1
fi
