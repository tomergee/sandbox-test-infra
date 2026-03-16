README
======

cluster-update.go is a tool that makes an asynchronous ClusterUpdate request with a provided update.

Usage
-----

```shell
go run cluster-update.go --cluster CLUSTER_NAME --project PROJECT --location LOCATION --patch CLUSTER_PATCH
```

for example:

```shell
go run update.go --cluster jasion-test --project 202196475689 --location us-central1-a --patch '{"update": {"kspanConfig": {"main": {"mode": "PROXY_TO_ETCD"}, "events": {"mode": "PROXY_TO_ETCD"}}}}'
```

The tool is using v1alpha1 api and taking host name from `CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER` env variable, which is set by ProwJob based on the --gke-environment parameter in the job definition and defaults to https://container.googleapis.com/.

ProwJob integration
-------------------

The tool can be used in Prow by adding a file with an exec command, e.g.:

```yaml
CL2_EXEC_COMMAND:
  - go
  - run
  - "../../../gke-internal.googlesource.com/test-infra/perf-tests/cluster-update/cluster-update.go"
  - --cluster=${CLUSTER_NAME}
  - --project=${PROJECT}
  - --location=${ZONE}
  - --patch=${CLUSTER_PATCH}
```

and adding this .yaml file as testoverrides parameter in a Prow job:

```yaml
  - --test-cmd-args=--testoverrides=../../../gke-internal.googlesource.com/test-infra/prow/gke-scalability-prow/config/gke/overrides/YOUR_FILE.yaml
```

Files with `CL2_EXEC_COMMAND` definition for zonal and regional clusters are located in `prow/gke-scalability-prow/config/gke/overrides/cluster_update_zonal.yaml` and `prow/gke-scalability-prow/config/gke/overrides/cluster_update_regional.yaml` respectively.

The `CLUSTER_NAME`, `PROJECT`, `ZONE` and `REGION` env variables are automatically populated and available to clusterLoader2. The `CLUSTER_PATCH` must be added in the job definition, e.g.:

```yaml
  - --env=CLUSTER_PATCH={"update":{"kspanConfig":{"main":{"mode":"PROXY_TO_ETCD"},"events":{"mode":"PROXY_TO_ETCD"}}}}
```
