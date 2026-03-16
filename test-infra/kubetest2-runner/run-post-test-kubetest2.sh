#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit


echo "⬇️ Dumping GKE logs..."
if [[ "${GKE_CLUSTER_LOCATIONS}" =~ -[a-z]$ ]]; then
  export ZONE="${GKE_CLUSTER_LOCATIONS}"
else
  export REGION="${GKE_CLUSTER_LOCATIONS}"
fi
"${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/run-gke-dump-logs-kubetest2.sh "$@"


echo "➡️ Running kubetest1 post-tests..."
"${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/run-post-test.sh "$@"
