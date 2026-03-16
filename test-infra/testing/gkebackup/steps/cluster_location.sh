#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

resolve_cluster_location() {
  if [[ -v REGION ]]; then
    export CLUSTER_LOCATION="${REGION}"
  elif [[ -v ZONE ]]; then
    export CLUSTER_LOCATION="${ZONE}"
  else
    echo "Missing required REGION or ZONE variables."
    exit 1
  fi
}