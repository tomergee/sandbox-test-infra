#!/bin/bash -xe

# Inputs
export ENV=staging
export CLUSTER=bayer-pvm-15k-test
export PROJECT=gke-scalability-cluster-15k-3
export VERSION=1.17.1-beta.0.384+eap-scalability-15k-dev-e945fe4942596a

export CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER="https://${ENV}-container.sandbox.googleapis.com/"
RUN_DATE="$(date +%Y-%m-%dT%H-%M-%S)"
export RUN_DATE
export TMP="${HOME}/logs/bayer-15k-${RUN_DATE}"
mkdir -p "$TMP"
export KUBECONFIG=$TMP/kubeconfig
echo "export TMP='${TMP}'"
echo "export KUBECONFIG='${KUBECONFIG}'"

# Tear-down previous.
gcloud --project=$PROJECT compute firewall-rules delete prom-allow-bayer-pvm-15k-test --quiet || true
gcloud container clusters --project=$PROJECT delete bayer-pvm-15k-test --region=us-central1 --quiet || true
gcloud compute --project=${PROJECT} networks delete ${CLUSTER} --quiet || true

# Create cluster.
gcloud compute --project=${PROJECT} networks create ${CLUSTER} --subnet-mode=custom
gcloud alpha container clusters create \
    --no-enable-stackdriver-kubernetes \
    --enable-ip-alias \
    --network=${CLUSTER} \
    --create-subnetwork name=bayer-subnet,range=/18 \
    --cluster-ipv4-cidr=/10 \
    --services-ipv4-cidr=/16 \
    --enable-private-nodes \
    --enable-master-authorized-networks \
    --master-authorized-networks=0.0.0.0/0 \
    --master-ipv4-cidr 172.16.1.0/28 \
    --project=${PROJECT} \
    --region=us-central1 \
    --machine-type=n1-highcpu-2 \
    --image-type=gci \
    --num-nodes=200 \
    --min-nodes=200 \
    --preemptible \
    --disk-size=50GB \
    --enable-autoscaling \
    --autoscaling-profile=optimize-utilization \
    --no-enable-autorepair \
    --cluster-version=${VERSION} \
    ${CLUSTER}

# Create heapster nodes.
gcloud container node-pools create --no-enable-autorepair --num-nodes=1 --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-standard-64 node-heapster

# WARM UP MASTER
echo "Warming up masters"
gcloud container node-pools create --no-enable-autorepair --num-nodes=1000 --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-highcpu-2 tmp-pool-0
gcloud container node-pools create --no-enable-autorepair --num-nodes=1000 --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-highcpu-2 tmp-pool-1
echo "Sleeping 25min"
sleep 25m
gcloud container node-pools delete --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 tmp-pool-0 --quiet
gcloud container node-pools delete --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 tmp-pool-1 --quiet
echo "Warm up complete"
# END WARM UP MASTER

# Create 4 node pools for CA to have the space to grow the cluster.
gcloud container node-pools create --no-enable-autorepair --preemptible --num-nodes=0 --enable-autoscaling --min-nodes=0 --max-nodes=1000 --disk-size=50GB --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-highcpu-2 node-pool-1
gcloud container node-pools create --no-enable-autorepair --preemptible --num-nodes=0 --enable-autoscaling --min-nodes=0 --max-nodes=1000 --disk-size=50GB --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-highcpu-2 node-pool-2
gcloud container node-pools create --no-enable-autorepair --preemptible --num-nodes=0 --enable-autoscaling --min-nodes=0 --max-nodes=1000 --disk-size=50GB --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-highcpu-2 node-pool-3
gcloud container node-pools create --no-enable-autorepair --preemptible --num-nodes=0 --enable-autoscaling --min-nodes=0 --max-nodes=1000  --disk-size=50GB --cluster ${CLUSTER} --project=${PROJECT} --region us-central1 --machine-type=n1-highcpu-2 node-pool-4

# Configure firewall rules and extract master ips for prometheus monitoring.
gcloud compute --project="$PROJECT" firewall-rules create --allow tcp:9090 --source-ranges 172.16.1.0/28 prom-allow-${CLUSTER} --network ${CLUSTER}
MASTER_INTERNAL_IP=$(kap cluster info get --env $ENV --location us-central1 --cluster_name ${CLUSTER} --project_id ${PROJECT?} | grep 'Internal IP Address used by VM: ' | awk '{print $7}' | paste -s -d, -)
export MASTER_INTERNAL_IP

# Run the tests.
cd "$GOPATH/src/k8s.io/perf-tests/clusterloader2"
./run-e2e.sh \
    --enable-prometheus-server=true \
    --experimental-gcp-snapshot-prometheus-disk=true \
    --experimental-prometheus-disk-snapshot-name="bayer-15k-${RUN_DATE}" \
    --prometheus-scrape-etcd=false \
    --provider=gke \
    --testconfig="$GOPATH/src/gke-internal/test-infra/perf-tests/testing/bayer/config.yaml" \
    --report-dir="$TMP" 2>&1 | tee "$TMP/cl2.log" || true

# Clean up
gcloud --project=$PROJECT compute firewall-rules delete prom-allow-bayer-pvm-15k-test --quiet || true
gcloud container clusters --project=$PROJECT delete bayer-pvm-15k-test --region=us-central1 --quiet || true
gcloud compute --project=${PROJECT} networks delete ${CLUSTER} --quiet || true
