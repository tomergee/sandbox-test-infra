#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

# shellcheck disable=SC1091
. ../../../gke-internal.googlesource.com/test-infra/perf-tests/testing/gkebackup/steps/cluster_location.sh
resolve_cluster_location

BACKUP_PLAN_NAME=$1
RESTORE_PLAN_NAME=$3
CLUSTER_FULL_NAME=projects/"${PROJECT}"/locations/"${CLUSTER_LOCATION}"/clusters/"${CLUSTER_NAME}"

echo "Creating RestorePlan ${RESTORE_PLAN_NAME}"
gcloud beta container backup-restore restore-plans create "${RESTORE_PLAN_NAME}" \
  --project="${PROJECT}" \
  --location=us-west1 \
  --all-namespaces \
  --namespaced-resource-restore-mode=delete-and-restore \
  --backup-plan=projects/"${PROJECT}"/locations/us-west1/backupPlans/"${BACKUP_PLAN_NAME}" \
  --cluster="${CLUSTER_FULL_NAME}" \
  --volume-data-restore-policy=restore-volume-data-from-backup
