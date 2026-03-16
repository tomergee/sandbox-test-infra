#!/bin/bash
# Usage: ./run-load-test.sh [config-name] [provider]
# Example: ./run-load-test.sh agent-sandbox-warmpool-load-test.yaml gke

CONFIG=$1
if [ -z "$CONFIG" ]; then
  CONFIG="agent-sandbox-warmpool-load-test.yaml"
fi

PROVIDER=$2
if [ -z "$PROVIDER" ]; then
  PROVIDER="gke"
fi

KUBECONFIG=$3
if [ -z "$KUBECONFIG" ]; then
  KUBECONFIG="$HOME/.kube/config"
fi

echo "Running load test with config: configs/$CONFIG"
echo "Provider: $PROVIDER"
echo "Kubeconfig: $KUBECONFIG"

./clusterloader2/clusterloader2 \
  --testconfig=configs/$CONFIG \
  --kubeconfig=$KUBECONFIG \
  --provider=$PROVIDER
