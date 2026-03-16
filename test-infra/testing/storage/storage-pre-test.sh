#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

enable_max_shares_storageclass=false
enable_parallelstore_storageclass=false
enable_filestore_storageclass=false
enable_lustre_storageclass=false
enable_regional_pdssd_storageclass=false

# This code scans through the positional args and sets up the necessary
# configurable knobs for creating feature specific resources
while [ $# -gt 0 ]; do
	case $1 in
		--enable-max-shares-storageclass)
			enable_max_shares_storageclass=true
			;;
		--enable-filestore-storageclass)
			enable_filestore_storageclass=true
			;;
		--enable-lustre-storageclass)
			enable_lustre_storageclass=true
			;;
		--enable-parallelstore-storageclass)
			enable_parallelstore_storageclass=true
			;;
		--enable-regional-pdssd-storageclass)
			enable_regional_pdssd_storageclass=true
			;;
		*)
			echo "Pre-test: WARNING: Unknown option (ignored): " "${1}"
			;;
	esac
	shift
done

echo "Pre-test: running perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh"
# shellcheck source=/dev/null
source "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/run-pre-test-kubetest2.sh --scale-kube-dns 1.5 --add-maintenance-exclusion

# Create storage classes

if $enable_filestore_storageclass; then
	echo "Pre-test: Creating Filestore storage class"
	kubectl apply -f "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/storage/filestore-storageclass.yaml
fi

if $enable_parallelstore_storageclass; then
	echo "Pre-test: Creating Parallelstore storage class"
	kubectl apply -f "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/storage/parallelstore-storageclass.yaml
fi

if $enable_lustre_storageclass; then
	echo "Pre-test: Creating Lustre storage class"
	kubectl apply -f "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/storage/lustre-storageclass.yaml
fi

if $enable_max_shares_storageclass; then
	echo "Pre-test: Creating storage classes for configurable max shares feature"
	kubectl apply -f "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/storage/storageclass-configurable-max-shares.yaml
fi

if $enable_regional_pdssd_storageclass; then
	echo "Pre-test: Creating storage class for regional PD SSD"
	kubectl apply -f "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/storage/regional-pd-storageclass.yaml
fi

