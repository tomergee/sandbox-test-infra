#!/usr/bin/env bash

set -o nounset
set -o pipefail
set -o errexit

SCRIPT_ROOT=$(dirname "${BASH_SOURCE[0]}")

# TODO(b/309413963): Create a separate container image and move all this
# Terraform-related utter piece of nastiness to the image's Dockerfile.
(
    mkdir -p "${HOME}/.terraform/bin"
    cd ~/.terraform
    gsutil cp gs://gke-scalability-binaries/terraform .
    chmod a+x terraform
    mv terraform bin/
    grep -o '\.terraform/bin' <<< "${PATH}" \
        || grep -H '\.terraform/bin' ~/.bashrc \
        || echo "export PATH=${PATH}:~/.terraform/bin" >> ~/.bashrc
)
# shellcheck source=/dev/null
source "${HOME}/.bashrc"
printenv

cd "${SCRIPT_ROOT}"

go run cmd/main.go "${@}"
