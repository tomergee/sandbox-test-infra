#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

echo "Copying TPU driver to OSS perf-test repository"


cp -r "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/dra/tpudriver" "${GOPATH}/src/k8s.io/perf-tests/clusterloader2/pkg/dependency/dra/manifests/"

echo "'tpudriver' copied successfully to OSS perf-test"

echo "Pre-test: running perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh"
# shellcheck source=/dev/null
source "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh --add-maintenance-exclusion  --pprof-enabled  --scale-kube-dns 1.5

