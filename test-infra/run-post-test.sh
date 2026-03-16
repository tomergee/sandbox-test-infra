#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

sleep_after_post_test="false"
sleep_after_post_test_timeout=""

while [ $# -gt 0 ]; do
	case $1 in
		--sleep-after-post-test)
			sleep_after_post_test="true"
            sleep_after_post_test_timeout=$2
            shift
			;;
		*)
			printf 'WARNING: Unknown option (ignored): %s\n' "$1"
			;;
	esac
	shift
done

# Run kaaS to refresh timestamps of links previously dumped to the Prow job's artifacts.
cd "${GOPATH}/src/gke-internal.googlesource.com/test-infra/perf-tests/karchive"
go run cmd/main.go refresh-links

if [ "${sleep_after_post_test}" == "true" ]; then
	echo "Post-test: trying to sleep for ${sleep_after_post_test_timeout}"
	sleep "${sleep_after_post_test_timeout}"
fi
