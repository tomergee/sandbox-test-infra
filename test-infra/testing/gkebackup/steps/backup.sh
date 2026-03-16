#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

BACKUP_PLAN_NAME=$1
BACKUP_NAME=$2

echo "Creating Backup ${BACKUP_NAME}"
gcloud beta container backup-restore backups create "${BACKUP_NAME}" \
  --project="${PROJECT}" \
  --location=us-west1 \
  --backup-plan="${BACKUP_PLAN_NAME}" \

# Check backup until it is completed.
state=""
while [[ $state != "SUCCEEDED" && $state != "FAILED" ]]
do
  state=$(gcloud beta container backup-restore backups describe "${BACKUP_NAME}" \
    --project="${PROJECT}" \
    --location=us-west1 \
    --backup-plan="${BACKUP_PLAN_NAME}" \
    --format="value(state)")
  echo "Backup current state is $state"
  sleep 30
done

echo "Backup is completed:"
gcloud beta container backup-restore backups describe "$BACKUP_NAME" \
  --project="${PROJECT}" \
  --location=us-west1 \
  --backup-plan="$BACKUP_PLAN_NAME"

if [[ $state == "FAILED" ]]
then
  echo "Backup failed, refer Backup resource for details"
  exit 1
fi
