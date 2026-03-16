#!/bin/bash

prodaccess

CLOUDSDK_API_CLIENT_OVERRIDES_COMPUTE=staging_v1 \
/google/data/ro/teams/cloud-sdk/gcloud auth login

CLOUDSDK_API_CLIENT_OVERRIDES_COMPUTE=staging_v1 \
/google/data/ro/teams/cloud-sdk/gcloud auth application-default login
