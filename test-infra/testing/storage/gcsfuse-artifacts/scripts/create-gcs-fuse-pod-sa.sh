#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

echo "Creating service account gcs-fuse-pod-sa"
kubectl create serviceaccount gcs-fuse-pod-sa --namespace "gcsfuse-scale-test-1"