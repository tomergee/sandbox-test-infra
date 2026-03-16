package config

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/google/shlex"
)

type Kubetest2RunnerOptions struct {
	Timeout               time.Duration
	PreTestCmd            string
	PostTestCmd           string
	Kubetest2Deployer     string
	Kubetest2DeployerArgs string
	Kubetest2Tester       string
	Kubetest2TesterArgs   string
	GproxyPatches         []string
	DumpConfigMaps        string
	Env                   []string
}

func (opts *Kubetest2RunnerOptions) ValidateFlags() error {
	if opts.Kubetest2Deployer == "" {
		return fmt.Errorf("--kubetest2-deployer is required")
	}
	if opts.Kubetest2DeployerArgs == "" {
		return fmt.Errorf("--kubetest2-deployer-args is required")
	}
	if opts.Kubetest2Tester == "" {
		return fmt.Errorf("--kubetest2-tester is required")
	}
	if opts.Kubetest2TesterArgs == "" {
		return fmt.Errorf("--kubetest2-tester-args is required")
	}
	return nil
}

func (opts *Kubetest2RunnerOptions) CreateTesterArgsSlice() ([]string, error) {
	testerArgsSlice, err := shlex.Split(opts.Kubetest2TesterArgs)
	if err != nil {
		return nil, err
	}
	return testerArgsSlice, nil
}

func (opts *Kubetest2RunnerOptions) CreateDeployerArgsSlice() ([]string, error) {
	deployerArgs := os.ExpandEnv(opts.Kubetest2DeployerArgs)
	deployerArgsSlice, err := shlex.Split(deployerArgs)
	if err != nil {
		return nil, err
	}
	for i, arg := range deployerArgsSlice {
		if strings.Contains(arg, "--cluster-version=gs://") {
			parts := strings.SplitN(arg, "=", 2)
			if len(parts) == 2 {
				resolvedVersion, err := resolveGCSVersion(parts[1])
				if err != nil {
					log.Fatalf("Failed to resolve version: %v", err)
				}
				deployerArgsSlice[i] = fmt.Sprintf("%s=%s", parts[0], resolvedVersion)
				log.Printf("Resolved %s to %s", parts[1], resolvedVersion)
			}
		}
	}
	return deployerArgsSlice, nil
}

func resolveGCSVersion(input string) (string, error) {
	if !strings.HasPrefix(input, "gs://") {
		return input, nil
	}

	cmd := exec.Command("gsutil", "cat", input)
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return "", fmt.Errorf("gsutil failed for %q: %v, stderr: %s", input, err, string(exitErr.Stderr))
		}
		return "", fmt.Errorf("failed to run gsutil for %q: %v", input, err)
	}

	v := strings.TrimSpace(string(output))
	v = strings.TrimPrefix(v, "v")

	return v, nil
}
