#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit


echo "📜 Running kubetest2 pre-tests..."


# run-pre-test.sh script is used for additional cluster configuration (it's called below).
# run-pre-test.sh script relies on env variables set by kubetest1 during '--up' step.
# kubetest2 also sets env variables during '--up' step. However, they have different names.
# So copying some of kubetest2's env variables to env variables compatible with run-pre-test.sh.
echo "📝 Copying kubetest2 env variables to env variables compatible with run-pre-test.sh..."

export CLUSTER_NAME="${GKE_CLUSTER_NAMES}"
export PROJECT="${GKE_CLUSTER_PROJECTS}"
export CLUSTER_LOCATION="${GKE_CLUSTER_LOCATIONS}"
export KUBE_GKE_NETWORK="${GKE_CLUSTER_NAMES}"

if [[ "${CLUSTER_LOCATION}" =~ -[a-z]$ ]]; then
  export ZONE="${CLUSTER_LOCATION}"
else
  export REGION="${CLUSTER_LOCATION}"
fi

echo "➡️ Running kubetest1 pre-tests..."
"${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/run-pre-test.sh "$@"

# Run kaaS to:
# 1) dump files containing debugging links to the Prow job's artifacts,
# 2) dump master internal IP addresses to a temporary file.
cd "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/karchive"
go run cmd/main.go dump-data --internal-ips-output=/tmp/master_internal_ips --public-ips-output=/tmp/master_public_ips

echo "⬇️ Dumping GKE logs..."
"${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/run-gke-dump-logs-kubetest2.sh
