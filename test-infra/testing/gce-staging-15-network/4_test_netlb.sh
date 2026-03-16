#!/bin/bash

set -euxo pipefail

RUNID=$1
RUNDATE="$(date +%Y-%m-%dT%H-%M-%S)"
DUMPDIR=~/log/gce-staging/netlb-test-$RUNDATE

GKECL_149847_1_18_ILB_TESTS=gs://gob-prow/ci/v1.18.4-gke.200.4+364a3290860306

# Stops kubetest from collecting the logs
export DUMP_ONLY_MASTER_LOGS=true

# Makes kubetest pick up the internal gcloud - only it understands GCE staging_v1
export PATH=/google/data/ro/teams/cloud-sdk/:$PATH
export CLOUDSDK_API_CLIENT_OVERRIDES_COMPUTE=staging_v1
export CLOUDSDK_CONTAINER_USE_APPLICATION_DEFAULT_CREDENTIALS=true

pushd "$GOPATH/src/k8s.io/kubernetes"

echo "Creating logs dump dir: $DUMPDIR"
mkdir -p "$DUMPDIR"

function on_exit {
  popd
  echo "Search for logs in $DUMPDIR"
}
trap on_exit EXIT

echo "Running kubetest"
time kubetest \
--extract=$GKECL_149847_1_18_ILB_TESTS \
--test \
--up=false \
--down=false \
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
--ginkgo-parallel=1 \
--test_args="--ginkgo.focus=should.only.allow.access.from.service.loadbalancer.source.ranges \
  --minStartupPods=8 \
  --gce-api-endpoint=https://www.googleapis.com/compute/staging_v1/ \
  --allowed-not-ready-nodes=1 \
  --node-schedulable-timeout=90m" \
--timeout=300m \
--node-tests=false 2>&1 | tee -a "$DUMPDIR/kubetest-test.log"
