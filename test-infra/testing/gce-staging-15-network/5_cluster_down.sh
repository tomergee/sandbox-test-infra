#!/bin/bash

set -euxo pipefail

RUNID=$1
RUNDATE="$(date +%Y-%m-%dT%H-%M-%S)"
DUMPDIR=~/log/gce-staging/down-$RUNDATE

# Stops kubetest from collecting the logs
export DUMP_ONLY_MASTER_LOGS=true

# Makes kubetest pick up the internal gcloud - only it understands GCE staging_v1
export PATH=/google/data/ro/teams/cloud-sdk/:$PATH
export CLOUDSDK_API_CLIENT_OVERRIDES_COMPUTE=staging_v1
export CLOUDSDK_CONTAINER_USE_APPLICATION_DEFAULT_CREDENTIALS=true

pushd "$GOPATH/src/k8s.io/kubernetes"

echo "Creating logs dump dir: $DUMPDIR"
mkdir -p "$DUMPDIR"

export KUBECONFIG=~/gce-staging-kubeconfig

function on_exit {
  echo "Search for logs in $DUMPDIR"
  popd
}
trap on_exit EXIT

echo "Running kubetest"
time kubetest \
--test=false \
--test-cmd=/bin/true \
--up=false \
--down \
--deployment=gke \
--provider=gke \
--cluster="gke-$RUNID" \
--gcp-network="gke-$RUNID" \
--gcp-node-image=gci \
--gcp-project=staging-stress-zone-test \
--gcp-region=europe-north1 \
--gke-command-group=alpha \
--gke-create-nat=true \
--gke-node-ports=tcp,udp \
--gke-environment=https://scalability-2-test-container.sandbox.googleapis.com/ \
--timeout=100m 2>&1 | tee -a "$DUMPDIR/kubetest-down-output.log"
