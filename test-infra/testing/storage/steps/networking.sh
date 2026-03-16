#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

# This file contains networking functions needed for some storage setup tests such as Parallelstore, Lustre instance provisioning.

ACTION_NAME=$1
NETWORK_NAME=$2
FIREWALL_RULE_NAME=$3
IP_RANGE_NAME=$4
NEEDS_PARALLELSTORE_CLEANUP=$5
NEEDS_LUSTRE_CLEANUP=$6

PROJECT_ID=$(gcloud config get-value project 2>&1 | head -n 1)

# Create IP range for VPC peering.
function createIPRange() {
  echo "Creating IP range for VPC peering"
  echo "PFS network name is ${NETWORK_NAME}"
  gcloud compute addresses create "${IP_RANGE_NAME}" \
      --global \
      --purpose=VPC_PEERING \
      --prefix-length=24 \
      --description="PFS VPC Peering" \
      --network="${NETWORK_NAME}" \
      --project="${PROJECT_ID}"
}

# Create firewall rules for communicating with the service.
function createFirewallRule() {
  echo "Extracting CIDR range"
  CIDR_RANGE=$(
    gcloud compute addresses describe "${IP_RANGE_NAME}" \
      --global  \
      --format="value[separator=/](address, prefixLength)" \
      --project="${PROJECT_ID}"
  )

  echo "Creating firewall rules"
  gcloud compute firewall-rules create "${FIREWALL_RULE_NAME}" \
    --allow=tcp \
    --network="${NETWORK_NAME}" \
    --source-ranges="${CIDR_RANGE}" \
    --project="${PROJECT_ID}"
}

# Peer servicenetworking API with the network.
function createVPCPeering() {
  echo "Peering servicenetworking API with the network"
  RESULT=$(gcloud services vpc-peerings connect \
    --network="${NETWORK_NAME}" \
    --project="${PROJECT_ID}" \
    --ranges="${IP_RANGE_NAME}" \
    --service=servicenetworking.googleapis.com \
    2>&1)

  if [[ $? -ne 0 && "${RESULT}" == *"FLOW_SN_PF_UPDATE_PEERING_MODIFY_RANGE_IN_CREATE"*  ]]; then
    echo "Peering servicenetworking API with the network failed because it might already be enabled on this network. Attempting to update the IP range instead..."
    gcloud services vpc-peerings update \
      --network="${NETWORK_NAME}" \
      --project="${PROJECT_ID}" \
      --ranges="${IP_RANGE_NAME}" \
      --service=servicenetworking.googleapis.com \
      --force
  fi
}

# Cleanup VPC peerings.
function cleanupVPCPeering() {
  echo "Deleting peered servicenetworking API with the network"
  gcloud services vpc-peerings delete \
    --network="${NETWORK_NAME}" \
    --project="${PROJECT_ID}" \
    --service=servicenetworking.googleapis.com
}

# Cleanup firewall rules for communicating with the service.
function cleanupFirewallRule() {
  echo "Deleting firewall rules"
  gcloud compute firewall-rules delete "${FIREWALL_RULE_NAME}" \
    --project="${PROJECT_ID}"
}

# Cleanup IP range for VPC peering.
function cleanupIPRange() {
  echo "Deleting IP range for VPC peering"
  gcloud compute addresses delete "${IP_RANGE_NAME}" \
      --global \
      --project="${PROJECT_ID}"
}

# Function to check if the Parallelstore instance list is empty
function parallelstoreInstancesEmpty() {
    # TODO(urielguzman): Stop using alpha when we know how to update the gcloud command to the latest version.
    OUTPUT=$(gcloud alpha parallelstore instances list --project="${PROJECT_ID}" --location=-  2>&1)
    if [[ "${OUTPUT}" == *"Listed 0 items."* ]]; then
        return 0
    else
       echo "Found Parallelstore instances:"
       echo "${OUTPUT}"
       return 1
    fi
}

# Function to check if the Lustre instance list is empty
function lustreInstancesEmpty() {
    OUTPUT=$(gcloud lustre instances list --project="${PROJECT_ID}" --location=-  2>&1)
    if [[ "${OUTPUT}" == *"Listed 0 items."* ]]; then
        return 0
    else
       echo "Found Lustre instances:"
       echo "${OUTPUT}"
       return 1
    fi
}

# Wait for Parallelstore instances to be gone. Even if we wait for PVCs to delete that does not guarantee
# that Parallelstore instances are not using the VPC peering anymore so we must wait.
function waitForParallelstoreInstancesToBeEmpty() {
  echo "Waiting for Parallelstore instances to be deleted."
  TIMEOUT_S=1200  # 20m
  START_TIME=$(date +%s)

  while ! parallelstoreInstancesEmpty; do
    echo "Parallelstore instances still exist. Waiting..."
    ELAPSED_TIME_S=$(($(date +%s) - START_TIME))
    if [[ $ELAPSED_TIME_S -ge $TIMEOUT_S ]]; then
        echo "Timeout reached. Parallelstore instances may not have been deleted yet."
        return 1
    fi
    sleep 5
  done

  echo "There are no active Parallelstore instances."
  return 0
}

# Wait for Lustre instances to be gone. Even if we wait for PVCs to delete that does not guarantee
# that Lustre instances are not using the VPC peering anymore so we must wait.
function waitForLustreInstancesToBeEmpty() {
  echo "Waiting for Lustre instances to be deleted."
  TIMEOUT_S=2400  # 40m
  START_TIME=$(date +%s)

  while ! lustreInstancesEmpty; do
    echo "Lustre instances still exist. Waiting..."
    ELAPSED_TIME_S=$(($(date +%s) - START_TIME))
    if [[ $ELAPSED_TIME_S -ge $TIMEOUT_S ]]; then
        echo "Timeout reached. Lustre instances may not have been deleted yet."
        return 1
    fi
    sleep 5
  done

  echo "There are no active Lustre instances."
  return 0
}

case $ACTION_NAME in
  create)
    createIPRange
    createFirewallRule
    createVPCPeering
    ;;
  delete)
    if [[ "${NEEDS_PARALLELSTORE_CLEANUP}" == "true" ]]; then
      waitForParallelstoreInstancesToBeEmpty
    fi
    if [[ "${NEEDS_LUSTRE_CLEANUP}" == "true" ]]; then
      waitForLustreInstancesToBeEmpty
    fi
    cleanupVPCPeering
    cleanupFirewallRule
    cleanupIPRange
    ;;
  *)
    echo "Unknown action name for networking.sh (ignored): " "${ACTION_NAME}"
    ;;
esac