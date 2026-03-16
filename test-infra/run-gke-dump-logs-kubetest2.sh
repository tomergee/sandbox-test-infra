#!/bin/bash

set -o nounset
set -o pipefail
set -o xtrace

minority_report_job=false

while [ $# -gt 0 ]; do
	case $1 in
		--minority-report-job)
			minority_report_job=true
			;;
		*)
			printf 'WARNING: Unknown option (ignored): %s\n' "$1"
			;;
	esac
	shift
done

if [ "$minority_report_job" == true ]; then
	minority_report_metadata="${ARTIFACTS}/minority-report.json"
	metadata="{\"COMPONENT\": \"${COMPONENT:-}\", \"COMPONENT_VERSION\": \"${COMPONENT_VERSION:-}\", \"SIMPLIFIED_SET\": \"${SIMPLIFIED_SET:-}\"}"
	echo "Dumping Minority Report-specific env vars to ${minority_report_metadata}"
	if [ -z "${COMPONENT:-}" ]; then
		echo "ERROR: missing \"COMPONENT\" environment variable!"
	fi
	if [ -z "${COMPONENT_VERSION:-}" ]; then
		echo "ERROR: missing \"COMPONENT_VERSION\" environment variable!"
	fi
	if [ -z "${SIMPLIFIED_SET:-}" ]; then
		echo "ERROR: missing \"SIMPLIFIED_SET\" environment variable!"
	fi
	echo "${metadata}" > "${minority_report_metadata}"
fi

if [ -z "${GKE_CLUSTER_NAMES:-}" ]; then
  echo "GKE_CLUSTER_NAMES env variable not set"
  exit 1
fi

if [ -z "${GKE_CLUSTER_PROJECTS:-}" ]; then
  echo "GKE_CLUSTER_PROJECTS env variable not set"
  exit 1
fi

HASH="$(gcloud container clusters describe "${GKE_CLUSTER_NAMES}" --zone "${GKE_CLUSTER_LOCATIONS}" --project "${GKE_CLUSTER_PROJECTS}" --format 'value(id)')"
echo "Found hash for {${GKE_CLUSTER_NAMES}, ${GKE_CLUSTER_LOCATIONS}, ${GKE_CLUSTER_PROJECTS}}: ${HASH}"

# Run kaaS to dump debugging links based on initial cluster data.
cd "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/karchive" || exit
go run cmd/main.go dump-data \
  --cluster-name "${GKE_CLUSTER_NAMES}" \
  --location "${GKE_CLUSTER_LOCATIONS}" \
  --project "${GKE_CLUSTER_PROJECTS}" \
  --hash "${HASH}"

