Twitter tests
-------------

### Usage

The following snippet makes the following assumptions:

-	Test config is fetched to `$GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter` directory.
-	The tested cluster is already created and kubeconfig in `KUBECONFIG` can be used to control it.
-	`https://github.com/kubernetes/perf-tests` is cloned to `$GOPATH/src/k8s.io/perf-tests`

	```bash
	cd $GOPATH/src/k8s.io/perf-tests/clusterloader2

	./run-e2e.sh \
	--enable-prometheus-server=true \
	--tear-down-prometheus-server=false \
	--prometheus-scrape-etcd=true \
	--provider=gce \
	--nodes=15000 \
	--testconfig $GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/config.yaml \
	--testoverrides $GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/spec.yaml
	```

	You can also add optional `--testoverride $GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/5k-scale.yaml` to reduce workload 10x.

	When `--enable-prometheus-server` is set, `monitoring/grafana` service is created in the tested cluster with some useful dashboards. It is available during the test and after the test (only if `--tear-down-prometheus-server=false` is used).

	`kubectl -n monitoring port-forward svc/grafana :3000` can be used to access the grafana.

	### Directory structure

	-	`spec/` - input files from the doc shared with us
	-	`overrides/` - config files in a format parsable by cluster loader
	-	`overrides/Makefile` - a logic to generate `overrides/` from `spec/
	-	`config.yaml` - the main config
