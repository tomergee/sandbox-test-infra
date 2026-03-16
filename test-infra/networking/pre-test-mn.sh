#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

cnet=1
yamls=""
declare -a rest_args

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extra-network)
      raw_input="$2"

      # 1. Split by semicolon ';' to get individual networks
      IFS=';' read -ra NETWORK_DEFS <<< "$raw_input"

      for net_def in "${NETWORK_DEFS[@]}"; do
        # [FIX] Replace commas with spaces so we can parse vpc/subnet/range
        # This allows the input to be: "vpc,subnet,range" (Space-free)
        net_def_clean=${net_def//,/ }

        # 2. Parse the individual components
        read -r vpc subnet range <<< "$net_def_clean"

        if [[ -n "$range" ]]; then
          # --- L3 MODE ---
          echo "Adding L3 configuration: $vpc, $subnet, $range (mn-net$cnet)..."
          yamls+="---
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: mn-net$cnet
spec:
  vpc: $vpc
  vpcSubnet: $subnet
  podIPv4Ranges:
    rangeNames:
    - $range
---
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: mn-net$cnet
spec:
  provider: GKE
  type: L3
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: mn-net$cnet
"
        else
          # --- DEVICE MODE ---
          echo "Adding Device configuration: $vpc, $subnet (mn-net$cnet)..."
          yamls+="---
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: mn-net$cnet
spec:
  vpc: $vpc
  vpcSubnet: $subnet
  deviceMode: NetDevice
---
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: mn-net$cnet
spec:
  provider: GKE
  type: Device
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: mn-net$cnet
"
        fi
        (( cnet++ ))
      done

      shift 2
      ;;
    *)
      rest_args+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$yamls" ]]; then
  echo "Applying Network Manifests..."
  kubectl apply -f - <<EOF
$yamls
EOF
fi

echo "Waiting for all networks to be Ready..."
# The '|| true' ensures the script doesn't crash if the wait times out,
# though for a test you might prefer it to fail.
kubectl wait --for=condition=Ready network --all --timeout=5m || echo "WARNING: Timeout waiting for networks"

echo "Pre-test: running perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh"
# shellcheck source=/dev/null
source "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh --scale-kube-dns 1.5 --add-maintenance-exclusion

