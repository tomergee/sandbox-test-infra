package kaas

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"

	v1 "sigs.k8s.io/prow/pkg/apis/prowjobs/v1"
)

const (
	gkeApiEndpointEnvVarName = "CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER"
	jobSpecEnvVarName        = "JOB_SPEC"
	clusterVersionEnvVarName = "CLUSTER_API_VERSION"
)

var (
	envRegex        = regexp.MustCompile(`https://([^ ]+)-container\.sandbox\.googleapis\.com/?`)
	sandboxEnvRegex = regexp.MustCompile(`https://([^ ]+)-test-container\.sandbox\.googleapis\.com/?`)
	prodEnvRegex    = regexp.MustCompile(`https://container\.googleapis\.com/?`)
)

// Provides data accessible from within the test pod container.
func getJobInfo() (*JobInfo, error) {
	jobDuration, err := getJobDuration()
	if err != nil {
		return nil, err
	}

	jobStartTimestamp, err := getJobStartTimestamp()
	if err != nil {
		return nil, err
	}

	environment, isSandbox, err := getClusterEnvironment()
	if err != nil {
		return nil, err
	}

	return &JobInfo{
		JobStartTimestamp:  jobStartTimestamp,
		JobFinishTimestamp: jobStartTimestamp.Add(jobDuration),
		Environment:        environment,
		IsSandbox:          isSandbox,
		ClusterVersion:     os.Getenv(clusterVersionEnvVarName),
	}, nil
}

// Returns the Prow job's timeout value as the upper bound on the job's duration.
func getJobDuration() (time.Duration, error) {
	jobSpecEnv := os.Getenv(jobSpecEnvVarName)
	jobSpec := v1.ProwJobSpec{}

	if err := json.Unmarshal([]byte(jobSpecEnv), &jobSpec); err != nil {
		return time.Duration(0), fmt.Errorf("problem with JSON conversion: %w", err)
	}
	if jobSpec.DecorationConfig == nil || jobSpec.DecorationConfig.Timeout == nil {
		return time.Duration(0), fmt.Errorf("%s env var configured incorrectly", jobSpecEnvVarName)
	}
	return jobSpec.DecorationConfig.Timeout.Duration, nil
}

// Returns the Unix epoch timestamp of the test container's init process start time.
func getJobStartTimestamp() (time.Time, error) {
	cmd := exec.Command("ps", "-o", "etimes=", "-p", "1")
	output, err := cmd.Output()
	if err != nil {
		return time.Time{}, err
	}
	timeElapsed, err := strconv.ParseInt(strings.TrimSpace(string(output)), 10, 64)
	if err != nil {
		return time.Time{}, err
	}
	return time.Now().Add(time.Duration(-timeElapsed) * time.Second), nil
}

// Returns the name of the environment in which the GKE cluster lives.
func getClusterEnvironment() (string, bool, error) {
	gkeApiEndpoint := os.Getenv(gkeApiEndpointEnvVarName)
	if gkeApiEndpoint == "" || prodEnvRegex.MatchString(gkeApiEndpoint) {
		return "prod", false, nil
	}

	if match := sandboxEnvRegex.FindStringSubmatch(gkeApiEndpoint); len(match) > 0 {
		return match[1], true, nil
	}

	match := envRegex.FindStringSubmatch(gkeApiEndpoint)
	if len(match) == 0 {
		return "", false, fmt.Errorf("unrecognized %s env var pattern: %s", gkeApiEndpointEnvVarName, gkeApiEndpoint)
	}
	return match[1], false, nil
}
