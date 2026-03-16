#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

scraper_config_enabled=true
pprof_enabled=false
scale_kube_dns=false
scale_kube_dns_by="0"
add_maintenance_exclusion=false
use_coredns=false
coredns_cpu="100m"
coredns_memory="100Mi"
coredns_replicas="3"
num_pools="1"
add_proxy_subnet=false
proxy_subnet_range="192.168.254.0/23"
pre_test_sleep=0
enable_cilium_debug=false
# These test specific flags are required for Multi subnet clusters(MSC). To test MSC,
# the addition of the additional subnet can only be done through a cluster update and
# this script tracks the completion of cluster creation so this logic must go here.
test_msc=false
test_msc_1k=false
test_msc_5k=false

join_arr() {
	local IFS="$1"
	shift
	echo "$*"
}

setup_test_for_msc() {
	# begin capturing timing information
	local OLD_PS4="${PS4}"
  	export PS4='+ [$(date "+%Y-%m-%d %H:%M:%S")] '
	set -x
	echo "Pre-test: Enabling MSC, Updating cluster"
	gcloud container clusters update "${CLUSTER_NAME}" --additional-ip-ranges=subnetwork=subnet-add1,pod-ipv4-range=subnet-add1-sec --region="${cluster_location}"

	echo "Creating nodepool"
	gcloud container node-pools create test-msc-pool --cluster="${CLUSTER_NAME}" --num-nodes=96 --region="${cluster_location}" --disk-size=50 --timeout=3600

	set +x
	export PS4="${OLD_PS4}"
	# end capturing timing information

}

setup_test_for_msc_1k() {
	# begin capturing timing information
	local OLD_PS4="${PS4}"
  	export PS4='+ [$(date "+%Y-%m-%d %H:%M:%S")] '
	set -x
	# TODO(kapoorne) Check whether we still need the gcloud update.
	echo "Pre-test: updating gcloud"
	gcloud components update
	echo "Pre-test: Enabling MSC for 1k, Updating cluster"
	gcloud container clusters update "${CLUSTER_NAME}" --additional-ip-ranges=subnetwork=subnet-add1,pod-ipv4-range=subnet-add1-sec --region="${cluster_location}"

	echo "Creating nodepool"
	gcloud container node-pools create test-msc-pool --cluster="${CLUSTER_NAME}" --num-nodes=997 --region="${cluster_location}" --disk-size=50 --timeout=3600

	set +x
	export PS4="${OLD_PS4}"
}

setup_test_for_msc_5k() {
	# begin capturing timing information
	local OLD_PS4="${PS4}"
  	export PS4='+ [$(date "+%Y-%m-%d %H:%M:%S")] '
	set -x
	echo "Pre-test: updating gcloud"
	gcloud components update
	echo "Pre-test: Enabling MSC for 5k, Updating cluster"
	echo "Updating cluster"
	gcloud container clusters update "${CLUSTER_NAME}" --additional-ip-ranges=subnetwork=subnet-add1,pod-ipv4-range=subnet-add1-sec --region="${cluster_location}"

	# A limit of 1000 nodes per node pool as detailed at https://cloud.google.com/kubernetes-engine/quotas
	# means that we need to create multiple 1000 node pools.

	# Loop to create nodepools 1 through 5
	for i in {1..5}
	do
	  POOL_NAME="test-msc-pool${i}"
	  NUM_NODES=1000

	  if [[ ${i} -eq 5 ]]; then
	    NUM_NODES=997
	  fi

	  echo "Creating nodepool ${i} (${POOL_NAME}) with ${NUM_NODES} nodes"
	  gcloud container node-pools create "${POOL_NAME}" \
	    --cluster="${CLUSTER_NAME}" \
	    --num-nodes="${NUM_NODES}" \
	    --region="${cluster_location}" \
	    --disk-size=50 \
	    --timeout=3600
	done

	set +x
	export PS4="${OLD_PS4}"
}

# Run kaaS to:
# 1) dump files containing debugging links to the Prow job's artifacts,
# 2) dump master internal IP addresses to a temporary file.
cd "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/karchive"
go run cmd/main.go dump-data --internal-ips-output=/tmp/master_internal_ips --public-ips-output=/tmp/master_public_ips

cluster_location=${REGION:-${ZONE}}
if [[ ! -v cluster_location ]]; then
	echo "Cannot determine cluster location. Missing required REGION or ZONE variables"
	exit 1
fi


echo "Waiting for cluster '$CLUSTER_NAME' in location '$cluster_location' to become 'RUNNING'..."

while true; do
  # Get the current status of the cluster
  STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --location "$cluster_location" --project="${PROJECT}" --format="value(status)" 2>/dev/null)

  # Check the status
  if [ "$STATUS" == "RUNNING" ]; then
    echo "Cluster '$CLUSTER_NAME' is now RUNNING."
    break
  elif [ "$STATUS" == "ERROR" ]; then
    echo "Cluster '$CLUSTER_NAME' is in an ERROR state."
    exit 1
  elif [ -z "$STATUS" ]; then
    echo "Could not retrieve status for cluster '$CLUSTER_NAME'. It may not exist or you may lack permissions."
    exit 1
  else
    echo "Current status is '$STATUS'. Waiting..."
    # Wait for 60 seconds before checking again
    sleep 600
  fi
done

# If the cluster is created with --enable-master-authorized-networks to prevent
# public access (go/limit-access-scalability-tests), only specified authorized
# networks can access the control plane. AUTH_NETWORK_ADDR variable is used to
# specify the trusted IP addresses when the cluster is first created. Here, we
# add the NAT IPs of the test cluster to the authorized networks list to enable
# control plane access from the test cluster.
master_authorized_networks_enabled=$(
	gcloud container clusters describe "${CLUSTER_NAME}"\
		--project="${PROJECT}" \
		--location="${cluster_location}" \
		--format="value(masterAuthorizedNetworksConfig.enabled)"
)
if [[ -n "$master_authorized_networks_enabled" ]]; then
	echo "Pre-test: Adding NAT IPs to master authorized networks"
	router_infos=$(
		gcloud compute routers list \
		--project="${PROJECT}" \
		--format="csv[no-heading](name,region)"
	)
	auth_networks=()
	auth_networks+=("${AUTH_NETWORK_ADDR:-}")
	while IFS= read -r router_info || [[ -n ${router_info} ]]; do
		router_name=$(echo "${router_info}" | cut -d',' -f1)
		router_region=$(echo "${router_info}" | cut -d',' -f2)
		retries=3
		for ((try=0; try<retries; try++)); do
			if [[ $try -gt 0 ]]; then
				echo "Couldn't get test cluster's Cloud NAT IP address. Retrying again in 30 seconds..."
				sleep 30
			fi
			nat_ip_list=$(
				gcloud compute routers get-nat-ip-info "${router_name}" \
				--region="${router_region}" \
				--project="${PROJECT}" \
				--format="value(result.natIpInfoMappings[].natIp)" \
				| tr -d "'[]"
			)
			if [[ -n $nat_ip_list ]]; then
				break
			fi
		done
		if [[ $try -eq $retries ]]; then
			echo "Couldn't get test cluster's Cloud NAT IP address after ${try} tries. Exiting."
			exit 1
		fi
		IFS=', ' read -r -a nat_ips <<< "$nat_ip_list"
		for nat_ip in "${nat_ips[@]}"; do
			auth_networks+=("${nat_ip}/32")
		done
	done < <(printf '%s' "${router_infos}")
	all_auth_networks=$(join_arr "," "${auth_networks[@]}")
	echo "Pre-test: Updating master authorized networks of ${CLUSTER_NAME} to ${all_auth_networks}"
	gcloud container clusters update "${CLUSTER_NAME}" \
		--enable-master-authorized-networks \
		--master-authorized-networks="${all_auth_networks}" \
		--location="${cluster_location}" --project="${PROJECT}"
fi

while [ $# -gt 0 ]; do
	case $1 in
		--pprof-enabled)
			pprof_enabled=true
			;;
		--turn-off-scraper-config)
			scraper_config_enabled=false
			;;
		--scale-kube-dns)
			scale_kube_dns=true
			scale_kube_dns_by=$2
			shift
			;;
		--add-maintenance-exclusion)
			add_maintenance_exclusion=true
			;;
		--num-pools)
			num_pools=$2
			shift
			;;
		--use-coredns)
			use_coredns=true
			;;
		--coredns-cpu)
			coredns_cpu=$2
			shift
			;;
		--coredns-memory)
			coredns_memory=$2
			shift
			;;
		--coredns-replicas)
			coredns_replicas=$2
			shift
			;;
		--add-proxy-subnet)
			add_proxy_subnet=true
			proxy_subnet_range=$2
			shift
			;;
		--pre-test-sleep)
			pre_test_sleep=$2
			shift
			;;
		--enable-cilium-debug)
			enable_cilium_debug=true
			;;
		--test-msc)
			test_msc=true
			;;
		--test-msc-1k)
			test_msc_1k=true
			;;
		--test-msc-5k)
			test_msc_5k=true
			;;
		*)
			printf 'WARNING: Unknown option (ignored): %s\n' "$1"
			;;
	esac
	shift
done

if [ "$scraper_config_enabled" == true ]; then
	echo "Pre-test: Configuring scraper-config ConfigMap (http://go/measuring-internal-gke-slislo-with-cl2)"
	scraper_ns_exists=$(kubectl get ns scraper --ignore-not-found | wc -l)
	if [[ "$scraper_ns_exists" -eq 0 ]]; then
		echo "Pre-test: Creating 'scraper' namespace"
		kubectl create namespace scraper
	fi
	scraper_cm_exists=$(kubectl get configmap -n scraper scraper-config --ignore-not-found | wc -l)
	if [[ "$scraper_cm_exists" -eq 0 ]]; then
		echo "Pre-test: Creating 'scraper-config' ConfigMap"
		kubectl create configmap -n scraper scraper-config --from-file "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/scraper-config.yaml"
	else
		echo "Pre-test: Skipping configuring 'scraper-config' ConfigMap, as it already exists"
	fi
fi

if [ "$add_maintenance_exclusion" == true ]; then
	if [[ -v REGION ]]; then
		location="--region=${REGION}"
	elif [[ -v ZONE ]]; then
		location="--zone=${ZONE}"
	else
		echo "Missing required REGION or ZONE variables"
		exit 1
	fi
	exclusion_exists=true
	exclusion_name="${CLUSTER_NAME}-exclusion"
	gcloud container clusters describe "${CLUSTER_NAME}" \
		--project "${PROJECT}" "${location}" | grep "${exclusion_name}" || exclusion_exists=false
	if [[ "${exclusion_exists}" == "true" ]]; then
		echo "Pre-test: Skipping configuring '${exclusion_name}' Maintenance Exclusion, as it already exists"
	else
		gcloud container clusters update "${CLUSTER_NAME}" \
			--add-maintenance-exclusion-name "${exclusion_name}" \
			--add-maintenance-exclusion-start "+P0S" \
			--add-maintenance-exclusion-end "+P2D" \
			--add-maintenance-exclusion-scope no_upgrades \
			--project "${PROJECT}" "${location}"
	fi
fi

if [ "$pprof_enabled" == true ]; then
	scraper_ns_exists=$(kubectl get ns scraper --ignore-not-found | wc -l)
	if [[ "$scraper_ns_exists" -eq 0 ]]; then
		echo "Pre-test: Creating 'scraper' namespace"
		kubectl create namespace scraper
	fi
	echo "Pre-test: Creating ConfigMap for pprof"
	kubectl apply -f "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/pprof.yaml"
fi

# When running high pod density tests (110/256 pods per node) kubedns is a bit
# overloaded. For such cases we need to increase the number of kubedns pods.
# It is also possible to get rid of kubedns from the cluster altogether by
# scaling down the kubedns-related deployments to zero replicas.
if [ "$scale_kube_dns" == true ]; then
	if [ "$scale_kube_dns_by" != "0" ] && [ "$scale_kube_dns_by" != "0.0" ]; then
		echo "Pre-test: Scaling the kubedns by a factor of ${scale_kube_dns_by}"
		coresPerReplica=$(echo "print(int(256/${scale_kube_dns_by}))" | python3)
		nodesPerReplica=$(echo "print(int(16/${scale_kube_dns_by}))" | python3)
		kubeCtlPatch="{\"data\":{\"linear\": \"{\\\"coresPerReplica\\\":${coresPerReplica},\\\"nodesPerReplica\\\":${nodesPerReplica},\\\"preventSinglePointFailure\\\":true}\"}}"
		echo "Pre-test: Patching kubedns autoscaler configmap: ${kubeCtlPatch}"

		# Retry logic has been added because kube-dns-autoscaler configmap is created
		# asynchronously and in rare cases it was not created in time b/204295842
		for x in $(seq 1 30); do
			if kubectl patch -n kube-system configmap/kube-dns-autoscaler --type merge --patch \ "${kubeCtlPatch}"; then
				break
			elif [[ $x != "30" ]]; then
				echo "Failed to patch kubedns autoscaler configmap. Retrying... $x"
				sleep 5
			else
				echo "ERROR: Failed to patch kubedns autoscaler configmap for the ${x}th time, exiting."
				exit 1
			fi
		done
	else
		# https://cloud.google.com/kubernetes-engine/docs/how-to/custom-kube-dns#scaling_down_kube-dns
		echo "Pre-test: Disabling kube-dns"
		kubectl scale deployment --replicas 0 kube-dns-autoscaler -n kube-system
		kubectl rollout status deployment kube-dns-autoscaler -n kube-system
		kubectl scale deployment --replicas 0 kube-dns -n kube-system
	fi
fi


if [ "${use_coredns}" == true ]; then
	echo "Pre-test: Enabling CoreDNS"
	corednstmp=$(mktemp -d)
	coredns_patch="${corednstmp}/patch.yaml"
	cat << EOF > "${coredns_patch}"
spec:
  replicas: ${coredns_replicas}
  template:
    spec:
      containers:
      - name: coredns
        resources:
          limits:
            memory: ${coredns_memory}
            cpu: ${coredns_cpu}
          requests:
            memory: ${coredns_memory}
            cpu: ${coredns_cpu}
EOF
	"${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/coredns/deploy.sh" | kubectl apply -f -
	echo "Pre-test: CoreDNS patching start"
	cat "${coredns_patch}"
	kubectl patch deployment coredns -n kube-system --patch-file "${coredns_patch}"
	echo "Pre-test: CoreDNS patching end"
fi

# applies group labels to nodes to group them into simulated node pools
if [ "$num_pools" -gt "1" ]; then
	num_nodes=$(kubectl get nodes | wc -l)
	num_nodes=$((num_nodes-1)) # minus 1 to exclude the column headers
	echo "Number of nodes: $num_nodes"
	echo "Number of nodepools: $num_pools"

	# group size = total nodes / num_pools.
	group_size=$(( num_nodes/num_pools ))
	if [ "$group_size" -eq "0" ]; then
		group_size=1
	fi
	echo "Group size: $group_size"

	# add group number as node label
	group=0
	count=0
	while read -r node; do
		echo "adding label group=$group to $node"
		kubectl label nodes "$node" group=$group
		count=$((count+1))
		if [ "$count" -ne "0" ] && (( (count % group_size) == 0 )); then
			group=$((group+1))
		fi
	done < <(kubectl get nodes | grep "-" | awk '{print $1}')
fi

if [ "$add_proxy_subnet" == true ]; then
	proxy_subnet_region=${REGION:-${ZONE::-2}}
	proxy_subnet_name=proxy-subnet-${proxy_subnet_region}
	echo "Creating proxy subnet ${proxy_subnet_name} under network ${KUBE_GKE_NETWORK}"
	gcloud compute networks subnets create "${proxy_subnet_name}" --project="${PROJECT}" --network="${KUBE_GKE_NETWORK}" --region="${proxy_subnet_region}" --range="${proxy_subnet_range}" --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
fi

if [ "$pre_test_sleep" -gt 0 ]; then
	echo "Sleeping for $pre_test_sleep seconds"
	sleep "$pre_test_sleep"
fi

if [ "$test_msc" == true ]; then
	setup_test_for_msc
fi

if [ "$test_msc_1k" == true ]; then
	setup_test_for_msc_1k
fi

if [ "$enable_cilium_debug" == true ]; then
	echo "Pre-test: Enabling Cilium debug logs"
	if kubectl get cm -n kube-system cilium-config &> /dev/null; then
		# Patch cilium-config to enable debug logs
		kubectl patch cm cilium-config -n kube-system -p '{"data":{"debug":"true"}}'
		# Restart anetd to pick up changes
		kubectl rollout restart ds/anetd -n kube-system
		# Wait for rollout
		kubectl rollout status ds/anetd -n kube-system --timeout=5m
	else
		echo "Pre-test: cilium-config ConfigMap not found, skipping debug enablement"
	fi
fi

if [ "$test_msc_5k" == true ]; then
	setup_test_for_msc_5k
fi
