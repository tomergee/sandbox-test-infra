#!/bin/bash

set -euxo pipefail

RUNID=$(python -c 'import random; import string; print "".join(random.choice(string.ascii_lowercase) for _ in range(5))')
RUNDATE="$(date +%Y-%m-%dT%H-%M-%S)"
DUMPDIR=~/log/gce-staging/up-$RUNDATE

GKECL_149847_1_18_ILB_TESTS=gs://gob-prow/ci/v1.18.4-gke.200.4+364a3290860306 # Build with custom l4 ilb tests

# We need to specify the shape in the following way because:
# 1. Not enough pd capcity in europe-north1-lj1 to create 15k nodes - being addressed in b/160339149
# 2. We cannot create non-default node pools larger than 500 nodes - b/160259280
# 3. Even if we had pd-capacity in europe-north1-lj1 then most likely it'd be faster to create node-pools 1by1
#    due to not enough "gce read requests per 100 seconds" quota in staging (4k vs 20k in prod for 15k ndoe clusters).
GKE_SHAPE='{
  "default": {
    "Nodes":2500,
    "MachineType":"g1-small",
    "ExtraArgs":["--disk-size=20GB"]
  },
  "heapster-pool": {
    "Nodes":1,
    "MachineType":"n1-standard-64"
  },
  "lj1-pool-1": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-2": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-3": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-4": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-5": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-6": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-7": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]}
  "lj1-pool-8": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-9": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-10": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-11": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-12": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-13": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]},
  "lj1-pool-14": {"Nodes":500, "MachineType":"g1-small", "ExtraArgs":["--disk-size=20GB", "--node-locations=europe-north1-lj1"]}
}'

# Stops kubetest from collecting the logs
export DUMP_ONLY_MASTER_LOGS=true

# Makes kubetest pick up the internal gcloud - only it understands GCE staging_v1
export PATH=/google/data/ro/teams/cloud-sdk/:$PATH
export CLOUDSDK_API_CLIENT_OVERRIDES_COMPUTE=staging_v1
export CLOUDSDK_CONTAINER_USE_APPLICATION_DEFAULT_CREDENTIALS=true

pushd "$GOPATH/src/k8s.io/kubernetes"

echo "Creating logs dump dir: $DUMPDIR"
mkdir -p "$DUMPDIR"

export KUBECONFIG=~/gce-staging-kubeconfig

function on_exit {
  popd

  echo "Search for logs in $DUMPDIR"
  echo "RUN_ID is $RUNID"
  echo "  Pass it to the test or down scripts"
}
trap on_exit EXIT

echo "Running kubetest"
time kubetest \
--extract=$GKECL_149847_1_18_ILB_TESTS \
--test=false \
--test-cmd=/bin/true \
--up \
--down=false \
--deployment=gke \
--provider=gke \
--cluster="gke-$RUNID" \
--gcp-network="gke-$RUNID" \
--gcp-node-image=gci \
--gcp-project=staging-stress-zone-test \
--gcp-region=europe-north1 \
--gke-node-locations=europe-north1-lj1,europe-north1-lm1,europe-north1-lq1 \
--gke-command-group=alpha \
--gke-create-nat=true \
--gke-node-ports=tcp,udp \
--gke-create-command="container clusters create \
  --no-enable-stackdriver-kubernetes \
  --enable-autorepair \
  --enable-ip-alias \
  --create-subnetwork range=/18 \
  --cluster-ipv4-cidr=/10 \
  --services-ipv4-cidr=/16 \
  --enable-private-nodes \
  --enable-master-authorized-networks \
  --master-authorized-networks=0.0.0.0/0 \
  --master-ipv4-cidr 172.16.0.0/28 \
  --no-enable-shielded-nodes \
  --no-shielded-secure-boot \
  --timeout=5000 \
  --enable-l4-ilb-subsetting" \
--gke-environment=https://scalability-2-test-container.sandbox.googleapis.com/ \
--gke-subnet-mode=custom \
--gke-shape="$GKE_SHAPE" \
--timeout=300m 2>&1 | tee -a "$DUMPDIR/kubetest-up-output.log"
