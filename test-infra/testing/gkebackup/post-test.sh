#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

# Clean up potential Backup for GKE resources leaks.
echo "Post-test: deleting Backup resources"
gcloud beta container backup-restore backups list --location=us-west1 --format="get(name)" | while read -r line; do
    echo "deleting $line"
    gcloud beta container backup-restore backups delete --location=us-west1 "$line" -q
  done

echo "Post-test: deleting BackupPlan resources"
gcloud beta container backup-restore backup-plans list --location=us-west1 --format="get(name)" | while read -r line; do
    echo "deleting $line"
    gcloud beta container backup-restore backup-plans delete --location=us-west1 "$line" -q --async
  done

echo "Post-test: deleting RestorePlan resources"
gcloud beta container backup-restore restore-plans list --location=us-west1 --format="get(name)" | while read -r line; do
    echo "deleting $line"
    gcloud beta container backup-restore restore-plans delete --location=us-west1 "$line" -q --async
  done

# Running general scalability post test
echo "Post-test: running perf-tests/kubetest2-runner/run-post-test-kubetest2.sh"
"${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/run-post-test-kubetest2.sh
