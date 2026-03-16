#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

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
# Set MASTER_INTERNAL_IP env var accordingly as clusterloader2 depends
# on its value to scrape some metrics (see b/193875853 for more details).
# Currently, this will work only for regional clusters. Zonal clusters don't have IP aliases.
setVariableFromFile MASTER_INTERNAL_IP /tmp/master_internal_ips

# PSC clusters are only available through public ips.
setVariableFromFile MASTER_IP /tmp/master_public_ips

# Invoke clusterloader2.
"${GOPATH}/src/k8s.io/perf-tests/run-e2e.sh" "${@}"
