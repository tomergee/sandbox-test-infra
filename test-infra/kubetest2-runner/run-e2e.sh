#!/bin/bash
# shellcheck disable=SC2086

set -o nounset
set -o pipefail
set -o errexit

if [[ "${GKE_CLUSTER_LOCATIONS}" =~ -[a-z]$ ]]; then
  export ZONE="${GKE_CLUSTER_LOCATIONS}"
  CLUSTER_API_VERSION=$(gcloud container clusters describe "${GKE_CLUSTER_NAMES}" \
    --zone "${GKE_CLUSTER_LOCATIONS}" \
    --project "${GKE_CLUSTER_PROJECTS}" \
    --format="value(currentMasterVersion)")
else
  export REGION="${GKE_CLUSTER_LOCATIONS}"
  CLUSTER_API_VERSION=$(gcloud container clusters describe "${GKE_CLUSTER_NAMES}" \
    --region "${GKE_CLUSTER_LOCATIONS}" \
    --project "${GKE_CLUSTER_PROJECTS}" \
    --format="value(currentMasterVersion)")
fi

echo "🌐 Setting up GKFE endpoint..."

IP_ENABLED=$(gcloud container clusters describe "$GKE_CLUSTER_NAMES" --location "$GKE_CLUSTER_LOCATIONS" --project="${GKE_CLUSTER_PROJECTS}" --format="value(controlPlaneEndpointsConfig.ipEndpointsConfig.enabled)")
if [[ "${IP_ENABLED}" == "False" ]]; then
  GKFE_CLUSTER_ENDPOINT=$(gcloud container clusters describe "$GKE_CLUSTER_NAMES" --location "$GKE_CLUSTER_LOCATIONS" --project="${GKE_CLUSTER_PROJECTS}" --format="value(controlPlaneEndpointsConfig.dnsEndpointConfig.endpoint)")
fi

function setVariableFromFile() {
    VARIABLE_NAME=$1
    FILE_TO_READ=$2
    if [[ ! -v "${VARIABLE_NAME}"  ]]; then
      if [[ ! -f "${FILE_TO_READ}" ]]; then
        echo "ERROR: failed to read ${FILE_TO_READ}. Please check if pre-test command with kaaS was run properly"
      else
        declare -gx "$VARIABLE_NAME=$(cat "${FILE_TO_READ}")"
      fi
    else
      declare -gx "$VARIABLE_NAME=${!VARIABLE_NAME}"
    fi
    echo "${VARIABLE_NAME} set to ${!VARIABLE_NAME}"
}

if [[ -z "${GKFE_CLUSTER_ENDPOINT:-}" ]]; then
  # Set MASTER_INTERNAL_IP env var accordingly as clusterloader2 depends
  # on its value to scrape some metrics (see b/193875853 for more details).
  # Currently, this will work only for regional clusters. Zonal clusters don't have IP aliases.
  setVariableFromFile MASTER_INTERNAL_IP /tmp/master_internal_ips

  # PSC clusters are only available through public ips.
  setVariableFromFile MASTER_IP /tmp/master_public_ips
fi

export CLUSTER_API_VERSION=${CLUSTER_API_VERSION:-}
export CLUSTER_LOCATION="${GKE_CLUSTER_LOCATIONS}"
export CLUSTER_NAME="${GKE_CLUSTER_NAMES}"
export MASTER_DNS_ENDPOINT=${GKFE_CLUSTER_ENDPOINT:-}
export MASTER_INTERNAL_IP=${MASTER_INTERNAL_IP:-}
export MASTER_IP=${MASTER_IP:-}
export PROJECT="${GKE_CLUSTER_PROJECTS}"

# Invoke clusterloader2.
"${GOPATH}/src/k8s.io/perf-tests/run-e2e.sh" cluster-loader2 "$@"

