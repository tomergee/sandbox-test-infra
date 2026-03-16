#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

cleanup_lustre_storage=false
cleanup_filestore_storage=false
cleanup_parallelstore_storage=false

# This code scans through the positional args and sets up the necessary
# configurable knobs for cleaning up feature specific resources
while [ $# -gt 0 ]; do
    case $1 in
        --cleanup-lustre-storage)
            cleanup_lustre_storage=true
            ;;
        --cleanup-filestore-storage)
            cleanup_filestore_storage=true
            ;;
        --cleanup-parallelstore-storage)
            cleanup_parallelstore_storage=true
            ;;
        *)
            echo "Post-test: WARNING: Unknown option (ignored): " "${1}"
            ;;
    esac
    shift
done

# Cleanup potential lustre leaks
if $cleanup_lustre_storage; then
    echo "Post-test: Deleting potential Lustre instance leaks"
    gcloud lustre instances list --location=- --format="value(name)" | while read -r line; do
        echo "deleting $line"
        gcloud lustre instances delete "$line" --location=- -q --async
    done
fi

# Cleanup potential filestore leaks
if $cleanup_filestore_storage; then
    echo "Post-test: Deleting potential Filestore instance leaks"
    gcloud filestore instances list --format="value(name)" | while read -r line; do
        echo "deleting $line"
        gcloud filestore instances delete "$line" --force --region us-central1 -q --async &>/dev/null
    done
fi

# Cleanup potential parallelstore leaks
if $cleanup_parallelstore_storage; then
    echo "Post-test: Deleting potential Parallelstore instance leaks"
    gcloud alpha parallelstore instances list --location=- --format="value(name)" | while read -r line; do
        echo "deleting $line"
        gcloud alpha parallelstore instances delete "$line" --location=- -q --async
    done
fi

# Running general scalability post test
echo "Post-test: running perf-tests/kubetest2-runner/run-post-test-kubetest2.sh"
"${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/run-post-test-kubetest2.sh
