package main

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/pkg/config"
)

func TestMain(m *testing.M) {
	initFlags()
	code := m.Run()
	os.Exit(code)
}

func TestFlagParsing(t *testing.T) {
	oldArgs := os.Args
	defer func() {
		os.Args = oldArgs
	}()

	tests := []struct {
		name            string
		args            []string
		expectedOptions *config.Kubetest2RunnerOptions
		wantErr         bool
		errMessage      error
	}{
		{
			name: "Default options",
			args: []string{"cmd", "--kubetest2-deployer=gke", "--kubetest2-deployer-args=--zone=us-central1-f", "--kubetest2-tester=clusterloader2", "--kubetest2-tester-args=--provider=gke"},
			expectedOptions: &config.Kubetest2RunnerOptions{
				Timeout:               0,
				PreTestCmd:            "",
				PostTestCmd:           "",
				Kubetest2Deployer:     "gke",
				Kubetest2DeployerArgs: "--zone=us-central1-f",
				Kubetest2Tester:       "clusterloader2",
				Kubetest2TesterArgs:   "--provider=gke",
				GproxyPatches:         []string{},
				Env:                   []string{},
				DumpConfigMaps:        "[]",
			},
			wantErr: false,
		},
		{
			name: "Flags set correctly",
			args: []string{"cmd",
				"--timeout=2h",
				"--pre-test-cmd=$GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/run-pre-test.sh --add-maintenance-exclusion  --pprof-enabled  --scale-kube-dns 1.5",
				"--post-test-cmd=$GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/run-post-test.sh",
				"--gproxy-patches=$TURN_ON_PRIVATE_PSC",
				"--gproxy-patches=$STORAGE_QUOTA_30GB",
				"--env=CL2_API_AVAILABILITY_PERCENTAGE_THRESHOLD=99.5",
				"--env=CL2_DELETE_NAMESPACE_TIMEOUT=20m",
				"--env=CL2_ENABLE_API_AVAILABILITY_MEASUREMENT=true",
				"--env=CL2_ENABLE_CONTAINER_RESTARTS_MEASUREMENT=true",
				"--env=CL2_ENABLE_DNSTESTS=true",
				"--env=CL2_ENABLE_NODE_LOCAL_DNS_LATENCY=true",
				"--env=CL2_ENABLE_QUOTAS_USAGE_MEASUREMENT=true",
				"--env=CL2_HUGE_SERVICE_ENDPOINTS=10000",
				"--env=CL2_LATENCY_POD_CPU=80",
				"--env=CL2_NODE_LOCAL_DNS_LATENCY_THRESHOLD=1s",
				"--env=CL2_SCHEDULER_THROUGHPUT_THRESHOLD=0",
				"--env=USE_GKE_GCLOUD_AUTH_PLUGIN=True",
				"--kubetest2-deployer=gke",
				"--kubetest2-deployer-args=" + strings.Join([]string{
					"--boskos-acquire-timeout-seconds=3600",
					"--cluster-name=perf-1-34-100",
					"--cluster-version=1.34",
					"--release-channel=rapid",
					"--boskos-resource-type=gke-scalability-100-project",
					"--zone=us-central1-f",
					"--gcloud-command-group=beta",
					`--create-command="container clusters create --addons=NodeLocalDNS --cluster-ipv4-cidr=/10 --create-subnetwork=range=/18 --enable-ip-alias --enable-master-authorized-networks --enable-private-nodes --logging=SYSTEM,WORKLOAD,API_SERVER,SCHEDULER,CONTROLLER_MANAGER --master-authorized-networks=${AUTH_NETWORK_ADDR} --master-ipv4-cidr=172.16.0.0/28 --monitoring=SYSTEM,API_SERVER,SCHEDULER,CONTROLLER_MANAGER --quiet --services-ipv4-cidr=/16"`,
					"--environment=staging",
					"--firewall-rule-allow=tcp:9091",
					"--machine-type=e2-medium",
					"--num-nodes=99",
					`--extra-nodepool="name=heapster-pool&machine-type=e2-standard-8&image-type=cos_containerd&num-nodes=1"`}, " "),
				"--kubetest2-tester=clusterloader2",
				"--kubetest2-tester-args=" + strings.Join([]string{
					"--repo-root=$GOPATH/src/k8s.io/perf-tests/",
					"--test-configs=testing/huge-service/config.yaml",
					"--test-configs=testing/load/config.yaml",
					"--test-overrides=../../../gke-internal.googlesource.com/test-infra/prow/gke-scalability-prow/config/gke/overrides/ignore-known-gke-restarts.yaml",
					"--test-overrides=./testing/experiments/enable_restart_count_check.yaml",
					"--test-overrides=./testing/experiments/use_simple_latency_query.yaml",
					"--test-overrides=./testing/overrides/load_throughput.yaml",
					"--provider=gke",
					"--report-dir=/tmp/artifacts",
					"--nodes=3"}, " ")},
			expectedOptions: &config.Kubetest2RunnerOptions{
				Timeout:           time.Hour * 2,
				PreTestCmd:        "$GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/run-pre-test.sh --add-maintenance-exclusion  --pprof-enabled  --scale-kube-dns 1.5",
				PostTestCmd:       "$GOPATH/src/gke-internal.googlesource.com/test-infra/perf-tests/run-post-test.sh",
				Kubetest2Deployer: "gke",
				Kubetest2DeployerArgs: strings.Join([]string{
					"--boskos-acquire-timeout-seconds=3600",
					"--cluster-name=perf-1-34-100",
					"--cluster-version=1.34",
					"--release-channel=rapid",
					"--boskos-resource-type=gke-scalability-100-project",
					"--zone=us-central1-f",
					"--gcloud-command-group=beta",
					`--create-command="container clusters create --addons=NodeLocalDNS --cluster-ipv4-cidr=/10 --create-subnetwork=range=/18 --enable-ip-alias --enable-master-authorized-networks --enable-private-nodes --logging=SYSTEM,WORKLOAD,API_SERVER,SCHEDULER,CONTROLLER_MANAGER --master-authorized-networks=${AUTH_NETWORK_ADDR} --master-ipv4-cidr=172.16.0.0/28 --monitoring=SYSTEM,API_SERVER,SCHEDULER,CONTROLLER_MANAGER --quiet --services-ipv4-cidr=/16"`,
					"--environment=staging",
					"--firewall-rule-allow=tcp:9091",
					"--machine-type=e2-medium",
					"--num-nodes=99",
					`--extra-nodepool="name=heapster-pool&machine-type=e2-standard-8&image-type=cos_containerd&num-nodes=1"`}, " "),
				Kubetest2Tester: "clusterloader2",
				Kubetest2TesterArgs: strings.Join([]string{
					"--repo-root=$GOPATH/src/k8s.io/perf-tests/",
					"--test-configs=testing/huge-service/config.yaml",
					"--test-configs=testing/load/config.yaml",
					"--test-overrides=../../../gke-internal.googlesource.com/test-infra/prow/gke-scalability-prow/config/gke/overrides/ignore-known-gke-restarts.yaml",
					"--test-overrides=./testing/experiments/enable_restart_count_check.yaml",
					"--test-overrides=./testing/experiments/use_simple_latency_query.yaml",
					"--test-overrides=./testing/overrides/load_throughput.yaml",
					"--provider=gke",
					"--report-dir=/tmp/artifacts",
					"--nodes=3"}, " "),
				GproxyPatches: []string{"$TURN_ON_PRIVATE_PSC", "$STORAGE_QUOTA_30GB"},
				Env: []string{"CL2_API_AVAILABILITY_PERCENTAGE_THRESHOLD=99.5",
					"CL2_DELETE_NAMESPACE_TIMEOUT=20m",
					"CL2_ENABLE_API_AVAILABILITY_MEASUREMENT=true",
					"CL2_ENABLE_CONTAINER_RESTARTS_MEASUREMENT=true",
					"CL2_ENABLE_DNSTESTS=true",
					"CL2_ENABLE_NODE_LOCAL_DNS_LATENCY=true",
					"CL2_ENABLE_QUOTAS_USAGE_MEASUREMENT=true",
					"CL2_HUGE_SERVICE_ENDPOINTS=10000",
					"CL2_LATENCY_POD_CPU=80",
					"CL2_NODE_LOCAL_DNS_LATENCY_THRESHOLD=1s",
					"CL2_SCHEDULER_THROUGHPUT_THRESHOLD=0",
					"USE_GKE_GCLOUD_AUTH_PLUGIN=True"},
				DumpConfigMaps: "[]",
			},
			wantErr: false,
		},
		{
			name: "Missing deployer",
			args: []string{"cmd", "--kubetest2-deployer-args=--zone=us-central1-f", "--kubetest2-tester=clusterloader2", "--kubetest2-tester-args=--provider=gke"},
			expectedOptions: &config.Kubetest2RunnerOptions{
				Timeout:               0,
				PreTestCmd:            "",
				PostTestCmd:           "",
				Kubetest2Deployer:     "",
				Kubetest2DeployerArgs: "--zone=us-central1-f",
				Kubetest2Tester:       "clusterloader2",
				Kubetest2TesterArgs:   "--provider=gke",
				GproxyPatches:         []string{},
				Env:                   []string{},
				DumpConfigMaps:        "[]",
			},
			wantErr:    true,
			errMessage: fmt.Errorf("--kubetest2-deployer is required"),
		},
		{
			name: "Missing deployer args",
			args: []string{"cmd", "--kubetest2-deployer=gke", "--kubetest2-tester=clusterloader2", "--kubetest2-tester-args=--provider=gke"},
			expectedOptions: &config.Kubetest2RunnerOptions{
				Timeout:               0,
				PreTestCmd:            "",
				PostTestCmd:           "",
				Kubetest2Deployer:     "gke",
				Kubetest2DeployerArgs: "",
				Kubetest2Tester:       "clusterloader2",
				Kubetest2TesterArgs:   "--provider=gke",
				GproxyPatches:         []string{},
				Env:                   []string{},
				DumpConfigMaps:        "[]",
			},
			wantErr:    true,
			errMessage: fmt.Errorf("--kubetest2-deployer-args is required"),
		},
		{
			name: "Missing tester",
			args: []string{"cmd", "--kubetest2-deployer=gke", "--kubetest2-deployer-args=--zone=us-central1-f", "--kubetest2-tester-args=--provider=gke"},
			expectedOptions: &config.Kubetest2RunnerOptions{
				Timeout:               0,
				PreTestCmd:            "",
				PostTestCmd:           "",
				Kubetest2Deployer:     "gke",
				Kubetest2DeployerArgs: "--zone=us-central1-f",
				Kubetest2Tester:       "",
				Kubetest2TesterArgs:   "--provider=gke",
				GproxyPatches:         []string{},
				Env:                   []string{},
				DumpConfigMaps:        "[]",
			},
			wantErr:    true,
			errMessage: fmt.Errorf("--kubetest2-tester is required"),
		},
		{
			name: "Missing tester args",
			args: []string{"cmd", "--kubetest2-deployer=gke", "--kubetest2-deployer-args=--zone=us-central1-f", "--kubetest2-tester=clusterloader2"},
			expectedOptions: &config.Kubetest2RunnerOptions{
				Timeout:               0,
				PreTestCmd:            "",
				PostTestCmd:           "",
				Kubetest2Deployer:     "gke",
				Kubetest2DeployerArgs: "--zone=us-central1-f",
				Kubetest2Tester:       "clusterloader2",
				Kubetest2TesterArgs:   "",
				GproxyPatches:         []string{},
				Env:                   []string{},
				DumpConfigMaps:        "[]",
			},
			wantErr:    true,
			errMessage: fmt.Errorf("--kubetest2-tester-args is required"),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			os.Args = test.args
			parseOptions()
			defer clearOptions()

			require.Equal(t, test.expectedOptions, opts)

			err := opts.ValidateFlags()
			if test.wantErr {
				require.Error(t, err, "Expected flag validation error")
				if test.errMessage.Error() != "" {
					require.Equal(t, err, test.errMessage)
				}
			} else {
				require.NoError(t, err, "Expected flag validation to pass")
			}
		})
	}
}

func clearOptions() {
	opts.Timeout = 0
	opts.PreTestCmd = ""
	opts.PostTestCmd = ""
	opts.Kubetest2Deployer = ""
	opts.Kubetest2DeployerArgs = ""
	opts.Kubetest2Tester = ""
	opts.Kubetest2TesterArgs = ""
	opts.GproxyPatches = []string{}
	opts.Env = []string{}
}
