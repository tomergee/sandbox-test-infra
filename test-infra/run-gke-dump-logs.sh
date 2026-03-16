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

# Get cluster data.
LOCATION=""
if [ -n "${ZONE:-}" ]; then
  LOCATION=${ZONE}
elif [ -n "${REGION:-}" ]; then
  LOCATION=${REGION}
else
  echo "Neither ZONE nor REGION env variable is set"
  exit 1
fi

if [ -z "${CLUSTER_NAME:-}" ]; then
  echo "CLUSTER_NAME env variable not set"
  exit 1
fi

if [ -z "${PROJECT:-}" ]; then
  echo "PROJECT env variable not set"
  exit 1
fi

HASH="$(gcloud container clusters describe "${CLUSTER_NAME}" --zone "${LOCATION}" --project "${PROJECT}" --format 'value(id)')"
echo "Found hash for {${CLUSTER_NAME}, ${LOCATION}, ${PROJECT}}: ${HASH}"

# Run kaaS to dump debugging links based on initial cluster data.
cd "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/karchive" || exit
go run cmd/main.go dump-data \
  --cluster-name "${CLUSTER_NAME}" \
  --location "${LOCATION}" \
  --project "${PROJECT}" \
  --hash "${HASH}"

