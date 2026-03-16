#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

# shellcheck disable=SC1091
. ../../../gke-internal.googlesource.com/test-infra/perf-tests/testing/gkebackup/steps/cluster_location.sh
resolve_cluster_location

BACKUP_PLAN_NAME=$1
CLUSTER_FULL_NAME=projects/"${PROJECT}"/locations/"${CLUSTER_LOCATION}"/clusters/"${CLUSTER_NAME}"

echo "Creating BackupPlan $BACKUP_PLAN_NAME"
gcloud beta container backup-restore backup-plans create "${BACKUP_PLAN_NAME}" \
  --project="${PROJECT}" \
  --location=us-west1 \
  --all-namespaces \
  --include-secrets \
  --include-volume-data \
  --cluster="${CLUSTER_FULL_NAME}"
