#!/bin/bash

VER=$1
if [ "$VER" = "" ]; then
  echo "Please specify version!!!"
  exit 1
fi
echo "Testing DPv2 version $VER..."
echo

echo "Authorizing with GKE Scalability Prow..."
gcloud container clusters get-credentials --project gke-scalability-prow prow --zone us-central1
echo

echo "Preparing config file..."
VER_ESC=${VER//\./\\\.}
cd ../../prow/gke-scalability-prow/config/gke || exit 1
cp dataplane-v2.yaml dataplane-v2.yaml.bak
sed -i "s/AA\.BB\.CC/$VER_ESC/g" dataplane-v2.yaml
echo

echo "Running test..."
export IGNORE_JOB_NAME_INCLUDES_USERNAME_TEST=true
./execute-prow-job.old.sh k8s-e2e-gke-5000-performance-dpv2-component-validation-manual
echo

echo "Restoring original file..."
mv dataplane-v2.yaml.bak dataplane-v2.yaml
