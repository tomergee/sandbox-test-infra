#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

BACKUP_PLAN_NAME=$1
BACKUP_NAME=$2
RESTORE_PLAN_NAME=$3
RESTORE_NAME=$4

echo "Creating Restore ${RESTORE_NAME}"
gcloud beta container backup-restore restores create "${RESTORE_NAME}" \
  --project="${PROJECT}" \
  --location=us-west1 \
  --restore-plan="${RESTORE_PLAN_NAME}" \
  --backup=projects/"${PROJECT}"/locations/us-west1/backupPlans/"${BACKUP_PLAN_NAME}"/backups/"${BACKUP_NAME}" \

# Check restore state until it is completed.
state=""
while [[ $state != "SUCCEEDED" && $state != "FAILED" ]]
do
  state=$(gcloud beta container backup-restore restores describe "${RESTORE_NAME}" \
    --project="${PROJECT}" \
    --location=us-west1 \
    --restore-plan="${RESTORE_PLAN_NAME}" \
    --format="value(state)")
  echo "Restore current state is $state"
  sleep 30
done

echo "Restore is completed:"
gcloud beta container backup-restore restores describe "${RESTORE_NAME}" \
  --project="${PROJECT}" \
  --location=us-west1 \
  --restore-plan="${RESTORE_PLAN_NAME}"

if [[ $state == "FAILED" ]]
then
  echo "Restore failed, refer Restore resource for details"
  exit 1
fi

# Since successful Restore may still contains in-progress VolumeRestores, we
# need to wait util all VolumeRestores are completed.

echo "Waiting all VolumeRestores to complete"
while true
do
  inProgressVRs=$(gcloud beta container backup-restore volume-restores list \
    --project="${PROJECT}" \
    --location=us-west1 \
    --restore-plan="${RESTORE_PLAN_NAME}" \
    --restore="${RESTORE_NAME}" \
    --filter="NOT state=(FAILED,SUCCEEDED)" \
    --format="get(name)")

  if [[ -z ${inProgressVRs} ]]; then
    # No in-progress VolumeRestores
    break
  fi

  # Contains in-progress VolumeRestores.
  vrCount=$(echo "${inProgressVRs}" | wc -l)
  echo "${vrCount} VolumeRestores are still in-progress."
  sleep 30
done

# Check if there are failed VolumeRestores.
failedVRs=$(gcloud beta container backup-restore volume-restores list \
  --project="${PROJECT}" \
  --location=us-west1 \
  --restore-plan="${RESTORE_PLAN_NAME}" \
  --restore="${RESTORE_NAME}" \
  --filter="state=(FAILED)" \
  --format="get(name)")

if [[ ${failedVRs} ]]; then
  # Contains failed VolumeRestores.
  echo "Some VolumeRestores are failed:"
  echo "${failedVRs}"
  exit 1
fi
echo "All VolumeRestores are completed successfully"
