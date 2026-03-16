package kaas

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestGetGKEAdminUIURL(t *testing.T) {
	cases := []struct {
		name     string
		dumper   *RunInfo
		expected string
	}{
		{
			name: "standard run in staging",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment: "staging",
					IsSandbox:   false,
				},
				ClusterInfo: &ClusterInfo{
					Hash: "fedcba9876543210",
				},
			},
			expected: "http://gke/fedcba9876543210?env=staging",
		},
		{
			name: "standard run in test",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment: "test",
					IsSandbox:   false,
				},
				ClusterInfo: &ClusterInfo{
					Hash: "fedcba9876543210",
				},
			},
			expected: "http://gke/fedcba9876543210?env=test",
		},
		{
			name: "scalability sandbox environment run",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment: "scalability-2",
					IsSandbox:   true,
				},
				ClusterInfo: &ClusterInfo{
					Hash: "fedcba9876543210",
				},
			},
			expected: "GKE Admin UI doesn't support sandbox",
		},
		{
			name: "standard run in staging, no hash",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment: "staging",
				},
				ClusterInfo: &ClusterInfo{},
			},
			expected: "no cluster hash provided",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.dumper.GetGKEAdminUIURL()
			if tc.expected != got {
				t.Errorf("GetGKEAdminUIURL(): expected: %q, got: %q", tc.expected, got)
			}
		})
	}
}

func TestGetAnalogUrl(t *testing.T) {
	cases := []struct {
		name           string
		dumper         *RunInfo
		process        string
		job            string
		expectedBase   string
		expectedParams url.Values
	}{
		{
			name: "standard run in staging",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "staging",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "fedcba9876543210",
					Location: "us-central1-f",
				},
			},
			process:      "apiserver",
			job:          "cluster_apiserver",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.process_name="apiserver" resource.labels.borg_user="cloud-kubernetes-staging" resource.labels.borg_job="staging.cloud_kubernetes.us-central1-f.cluster_apiserver" text_payload=~"fedcba9876543210"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
		{
			name: "standard run in prod",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "prod",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "fedcba9876543210",
					Location: "us-central1-f",
				},
			},
			process:      "apiserver",
			job:          "cluster_apiserver",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.process_name="apiserver" resource.labels.borg_user="cloud-kubernetes" resource.labels.borg_job="prod.cloud_kubernetes.us-central1-f.cluster_apiserver" text_payload=~"fedcba9876543210"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
		{
			name: "hostedmaster run in test",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "test",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "fedcba9876543210",
					Name:     "name",
					Location: "us-central1-f",
				},
			},
			process:      "hostedmaster",
			job:          "cluster_apiserver",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.process_name="hostedmaster" resource.labels.borg_user="cloud-kubernetes-test" resource.labels.borg_job="test.cloud_kubernetes.us-central1-f.cluster_apiserver" text_payload=~"name"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
		{
			name: "standard run in prod without hash",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "prod",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Name:     "name",
					Location: "us-central1-f",
				},
			},
			process:      "apiserver",
			job:          "cluster_apiserver",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.process_name="apiserver" resource.labels.borg_user="cloud-kubernetes" resource.labels.borg_job="prod.cloud_kubernetes.us-central1-f.cluster_apiserver" text_payload=~"name"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			expected := tc.expectedBase + tc.expectedParams.Encode()
			got := tc.dumper.GetAnalogURL(tc.process, tc.job)
			if expected != got {
				t.Errorf("getAnalogUrl(): expected: %q, got: %q", expected, got)
			}
		})
	}
}

func TestGetAnalogPodUrl(t *testing.T) {
	cases := []struct {
		name           string
		dumper         *RunInfo
		podNode        string
		expectedBase   string
		expectedParams url.Values
	}{
		{
			name: "standard run in staging",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "staging",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "fedcba9876543210",
					Location: "us-central1-f",
				},
			},
			podNode:      "cluster-server",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.borg_user="cloud-kubernetes-cluster-server-staging-jobs" resource.labels.borg_job="preprod-qual-us-central1-f.cluster-server" text_payload=~"fedcba9876543210"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
		{
			name: "standard run in prod",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "prod",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "fedcba9876543210",
					Location: "us-central1-f",
				},
			},
			podNode:      "cluster-server",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.borg_user="cloud-kubernetes-cluster-server" resource.labels.borg_job="prod-us-central1-f.cluster-server" text_payload=~"fedcba9876543210"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
		{
			name: "hostedmaster run in test",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "test",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "fedcba9876543210",
					Name:     "name",
					Location: "us-central1-f",
				},
			},
			podNode:      "hosted-master-server",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.borg_user="cloud-kubernetes-hosted-master-server-test-jobs" resource.labels.borg_job="autopush-qual-us-central1-f.hosted-master-server" text_payload=~"name"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
		{
			name: "standard run in prod without hash",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "prod",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Name:     "name",
					Location: "us-central1-f",
				},
			},
			podNode:      "cluster-server",
			expectedBase: "http://analog-ng/query?",
			expectedParams: url.Values{
				"text_query": []string{`resource.type="borg.producer" resource.labels.borg_user="cloud-kubernetes-cluster-server" resource.labels.borg_job="prod-us-central1-f.cluster-server" text_payload=~"name"`},
				"time_range": []string{"2021-05-03T00:00:00.00000Z/2021-05-03T01:00:00.00000Z"},
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			expected := tc.expectedBase + tc.expectedParams.Encode()
			got := tc.dumper.GetAnalogPodURL(tc.podNode)
			if expected != got {
				t.Errorf("GetAnalogPodUrl(): expected: %q, got: %q", expected, got)
			}
		})
	}
}

func copyFiles(src, dst string) error {
	files, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, f := range files {
		path := filepath.Join(src, f.Name())
		stat, err := os.Stat(path)
		if !stat.Mode().IsRegular() {
			continue
		}

		source, err := os.Open(path)
		if err != nil {
			continue
		}
		defer source.Close()

		dest, err := os.Create(fmt.Sprintf("%s/%s", dst, f.Name()))
		if err != nil {
			continue
		}
		defer dest.Close()
		_, err = io.Copy(dest, source)
		if err != nil {
			continue
		}
	}
	return nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil || !errors.Is(err, os.ErrNotExist)
}

func toNames(lg linkGroup) []string {
	res := []string{}
	for _, link := range lg.Links {
		res = append(res, link.Name)
	}
	return res
}

func slicesContainEqual(lhs, rhs []string) bool {
	temp := map[string]int{}
	for _, s := range lhs {
		temp[s] = temp[s] + 1
	}
	for _, s := range lhs {
		temp[s] = temp[s] - 1
	}
	for _, v := range temp {
		if v != 0 {
			return false
		}
	}
	return true
}

func TestFailedPods(t *testing.T) {
	cases := []struct {
		name                    string
		dumper                  *RunInfo
		artifactsPath           string
		podsDirectory           string
		expectedFailedPodsNames []string
	}{
		{
			name: "standard run",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "staging",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "jihgfedcba9876543210",
					Location: "us-central1-f",
				},
			},
			podsDirectory:           "test_data/empty",
			expectedFailedPodsNames: []string{},
		},
		{
			name: "single failed measurement run",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "staging",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "jihgfedcba9876543210",
					Location: "us-central1-f",
				},
			},
			podsDirectory: "test_data/single_failed",
			expectedFailedPodsNames: []string{
				"test-deployment-2-0-5979cfd959-76g86",
				"test-deployment-2-0-5979cfd959-ghkgf",
			},
		},
		{
			name: "multiple run",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "staging",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "jihgfedcba9876543210",
					Location: "us-central1-f",
				},
			},
			podsDirectory: "test_data/multiple_failed",
			expectedFailedPodsNames: []string{
				"test-deployment-2-0-5979cfd959-76g86",
				"test-deployment-2-0-5979cfd959-ghkgf",
				"test-statefulset-2-0-512gas2-f32tt",
				"test-statefulset-2-0-512gas2-gsdgf",
			},
		},
		{
			name: "multiple run",
			dumper: &RunInfo{
				JobInfo: &JobInfo{
					Environment:        "staging",
					JobStartTimestamp:  time.Unix(1620000000, 0),
					JobFinishTimestamp: time.Unix(1620003600, 0),
				},
				ClusterInfo: &ClusterInfo{
					Hash:     "jihgfedcba9876543210",
					Location: "us-central1-f",
				},
			},
			podsDirectory: "test_data/single_over_limit",
			expectedFailedPodsNames: []string{
				"test-deployment-2-0-5979cfd959-0",
				"test-deployment-2-0-5979cfd959-1",
				"test-deployment-2-0-5979cfd959-2",
				"test-deployment-2-0-5979cfd959-3",
				"test-deployment-2-0-5979cfd959-4",
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tempDir, err := os.MkdirTemp("", "")
			if err != nil {
				log.Fatal(err)
			}
			defer os.RemoveAll(tempDir) // clean up
			copyFiles(tc.podsDirectory, tempDir)

			os.Setenv(artifactsEnvVarName, tempDir)
			tc.dumper.DumpLinks()

			failedPodsPath := filepath.Join(tempDir, "failed-pods.link.json")

			if len(tc.expectedFailedPodsNames) == 0 {
				if fileExists(failedPodsPath) {
					t.Errorf("dumpLinks(): expected to not create failed pods but created one")
				} else {
					return
				}
			}

			if !fileExists(failedPodsPath) {
				t.Errorf("dumpLinks(): expected to create failed pods but created none")
			}

			f, err := os.Open(failedPodsPath)
			if err != nil {
				t.Errorf("dumpLinks(): could not open resulting failed pods file: %v", err)
			}
			lg := linkGroup{}
			err = json.NewDecoder(f).Decode(&lg)
			if err != nil {
				t.Errorf("dumpLinks(): could not unmarshal resulting failed pods file: %v", err)
			}
			podNames := toNames(lg)
			if !slicesContainEqual(tc.expectedFailedPodsNames, podNames) {
				t.Errorf("dumpLinks(): failed pods expected: %v got: %v", tc.expectedFailedPodsNames, podNames)
			}
		})
	}
}
