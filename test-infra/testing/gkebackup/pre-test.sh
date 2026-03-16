#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

echo "Pre-test: updating gcloud to latest version"
gcloud components update --quiet

echo "Pre-test: configuring Backup for GKE autopush service endpoint for gcloud"
gcloud config set api_endpoint_overrides/gkebackup https://autopush-gkebackup.sandbox.googleapis.com/

echo "Pre-test: running perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh"
# shellcheck source=/dev/null
source "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh --scale-kube-dns 1.5 --add-maintenance-exclusion

echo "Pre-test: creating Backup for GKE environment override ConfigMap"
kubectl apply -f "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/gkebackup/env_override.yaml
