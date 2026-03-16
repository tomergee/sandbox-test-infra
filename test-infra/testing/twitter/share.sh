#!/bin/bash
# shellcheck disable=SC2016 # I really want to change to $TESTCONFIG.
sed 's/\$GOPATH\/src\/gke-internal.googlesource.com\/test-infra\/perf-tests\/testing\/twitter/\$TESTCONFIG/g' < README.md > README-twitter.md
tar zcvf /tmp/config.tgz ./*.yaml README-twitter.md overrides/*.yaml
echo "/tmp/config.tgz created"
