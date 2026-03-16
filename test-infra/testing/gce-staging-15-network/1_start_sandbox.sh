#!/bin/bash

STARTDIR=$(pwd)
RUNID=$(python -c 'import random; import string; print "".join(random.choice(string.ascii_lowercase) for _ in range(5))')

DISABLE_SECURE_BOOT_PATCH=317109311 # Switches off master secure boot by hardcoding
DISABLE_MONITORING_PATCH=317653792 # Prevents monitoring server from reparing master
FIX_CNI_PLUGINS_VERSION_PATCH=317967067
OVERRIDE_L7_LB_CONTROLLER_IMAGE=318029088
FIX_TRANSIENT_MIRACL_ISSUES=318898537 # Fix transient miracl issues + use staging_v1 instead of cm_staging_v1 endpoint

KNOWN_GOOD_BASE=318054124 # CL that's been shows to start working sandboxes
SANDBOX_NAME=scalability-2

die() { echo "$*" 1>&2 ; exit 1; }

set -x

echo "Creating new citc client gkebox-$RUNID and patching CLs..."

# The double "p4 g4d" below is needed to make up for weird quirk of g4d
# https://yaqs.corp.google.com/eng/q/5835493401952256
p4 g4d -f --multichange "gkebox-$RUNID" || die "Failed to create citc client"
cd "$(p4 g4d "gkebox-$RUNID")" || exit
g4 sync @$KNOWN_GOOD_BASE
g4 patch -c $DISABLE_SECURE_BOOT_PATCH
g4 patch -c $DISABLE_MONITORING_PATCH
g4 patch -c $FIX_CNI_PLUGINS_VERSION_PATCH
g4 patch -c $OVERRIDE_L7_LB_CONTROLLER_IMAGE
g4 patch -c $FIX_TRANSIENT_MIRACL_ISSUES

HOSTED_MASTER_PROJECT=gke-scale-stress-hosted-master

# In case there's no resources in the cell, you'll need to find one with some
# space left: first find the cells where we have quota:
# https://viceroy.corp.google.com/flex_resources/consumer_table?min_uri=.*&consumer_groups=cloud-kubernetes-test&inventory_group=cloud-flex-pool&service_name=BORG&tier=TIER1.7_OR_BETTER
#
# Then search for them in http://worldmap/ to pick one from europe or US.
cat >/tmp/zones.textpb <<EOF
zones{zone:"europe-north1"cell:"wa"}
EOF

echo "Starting the sandbox"
# Starting the sandbox
# For some reason, sandboxes started in GCE staging don't pick up the
# right version maps; enabling conductor (enable_dvc_push_client=true)
# resolves the issue.
sandman cloud/kubernetes/engprod/gke_sandbox.gcl Build Setup Start \
--vars="jobs.sandbox_apis_manager=false,\
gke_zonal.hosted_master_project=$HOSTED_MASTER_PROJECT,\
gke_zonal.enable_dvc_push_client=true,\
gke_zonal.staging_gce=true,\
gke_global.staging_gce=true,\
name=${SANDBOX_NAME},\
ttl=30d,\
zones=$(cat /tmp/zones.textpb)" || die "Failed starting the sandbox"

echo "Deleting the citc client"
# Delete the citc client
cd "$STARTDIR" || exit
g4 citc -d -f "gkebox-$RUNID"
