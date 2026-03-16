package terraform

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"k8s.io/test-infra/kubetest/process"

	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/config"
)

type Scenario struct {
	name                 string
	directory            string
	applyRetries         int
	parallelism          int
	nodePoolResourceName string
	control              *process.Control
	proxyCmd             string
	proxyArgs            []string
}

func InitTerraform(scenario *Scenario, o *config.TftestOptions, c *process.Control) error {
	s, err := newScenario(o, c)
	if err != nil {
		log.Printf("Failed to initialize the Terraform scenario: %v", err)
		return err
	}
	*scenario = *s
	log.Printf("Initialized Terraform scenario %q", scenario)
	return nil
}

func newScenario(o *config.TftestOptions, control *process.Control) (*Scenario, error) {
	name := os.ExpandEnv(o.TfScenario)
	directory := name
	if index := strings.LastIndex(name, "/"); index != -1 {
		name = name[index+1:]
	}
	o.ProxyCmd = os.ExpandEnv(o.ProxyCmd)
	for i, arg := range o.ProxyArgs {
		o.ProxyArgs[i] = os.ExpandEnv(arg)
	}
	s := &Scenario{
		name:                 name,
		directory:            directory,
		applyRetries:         o.ApplyRetries,
		parallelism:          o.Parallelism,
		nodePoolResourceName: o.NodePoolName,
		control:              control,
		proxyCmd:             o.ProxyCmd,
		proxyArgs:            o.ProxyArgs,
	}
	if err := s.initTerraform(o.Project, o.ClusterName); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Scenario) terraformApply(timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := "terraform"
	args := []string{
		"apply",
		"--auto-approve",
		"--parallelism", strconv.Itoa(s.parallelism),
		"-no-color",
	}
	if s.proxyCmd != "" {
		cmd, args = s.getProxiedCmd(cmd, args)
	}
	return s.runCmd(ctx, cmd, args...)
}

func (s *Scenario) Apply(timeout time.Duration) error {
	var err error
	start := time.Now()
	for i := 0; i < s.applyRetries; i++ {
		if i > 0 {
			// Wait a minute and attempt to import state before retrying.
			//
			// This shouldn't really be necessary, as per the documentation Terraform
			// should refresh state as part of apply step. But in case of GKE node pools
			// it attempts to create them and fails apply with 'node pool already exists'
			// (see b/333971002).
			//
			// TODO(aleksandram): figure out why apply doesn't correctly reconcile state
			// specifically for GKE node pools.
			log.Printf("Sleeping for 1m before attempting to refresh state and retrying apply step.")
			time.Sleep(1 * time.Minute)
			if err := s.Refresh(10 * time.Minute); err != nil {
				log.Printf("Error attempting to refresh state: %v (attempt: %v)", err, i+1)
				continue
			}
		}
		if err = s.terraformApply(timeout); err != nil {
			log.Printf("error creating resources: %v (attempt: %v)", err, i+1)
			continue
		}
		// We want to assert timeout whether we succeeded or not.
		createDuration := time.Since(start)
		if createDuration > timeout {
			log.Printf("Creating resources took too long, not retrying after attempt %v: want less than %v, got %v", i+1, s.applyRetries, createDuration)
			return fmt.Errorf("creating resources took too long: want less than %v, got %v", s.applyRetries, createDuration)
		}
		log.Printf("Apply succeeded in attempt %d, took %v", i+1, createDuration)
		return err
	}
	return err
}

func (s *Scenario) Destroy(timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	return s.runCmd(
		ctx,
		"terraform",
		"destroy",
		"--auto-approve",
		"--refresh=false",
		"--parallelism", strconv.Itoa(s.parallelism),
		"-no-color",
	)
}

func (s *Scenario) Refresh(timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	return s.runCmd(
		ctx,
		"terraform",
		"apply",
		"--refresh-only",
		"--auto-approve",
		"--parallelism", strconv.Itoa(s.parallelism),
		"-no-color",
	)
}

func (s *Scenario) initTerraform(project, cluster string) error {
	// TODO: Remove not-generalized parameters
	params := map[string]string{
		"TFTEST_PROJECT_NAME":            project,
		"TFTEST_CLUSTER_NAME":            cluster,
		"TFTEST_NODE_POOL_RESOURCE_NAME": s.nodePoolResourceName,
	}

	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "TFTEST_") {
			continue
		}
		split := strings.SplitN(kv, "=", 2)
		if len(split) != 2 {
			return fmt.Errorf("unparsable string in os.Eviron(): %v", kv)
		}
		key, value := split[0], split[1]
		params[key] = value
	}
	log.Printf("Terraform parameters to be replaced: %v\n", params)

	files, err := getTerraformFiles(s.directory)
	if err != nil {
		return err
	}
	for _, fn := range files {
		log.Printf("Processing: %v\n", fn)
		if err := fillTerraformParams(fn, params); err != nil {
			return err
		}
	}
	return s.runCmd(context.Background(), "terraform", "init")
}

func (s *Scenario) runCmd(ctx context.Context, name string, args ...string) error {
	os.Chdir(s.directory)
	cmd := exec.CommandContext(ctx, name, args...)
	log.Printf("Running command: %s\n", cmd)
	return s.control.FinishRunning(cmd)
}

func (s *Scenario) String() string {
	return fmt.Sprintf("%s (directory: %s, parallelism: %d)", s.name, s.directory, s.parallelism)
}

func (s *Scenario) getProxiedCmd(name string, args []string) (string, []string) {
	proxyArgs := append(s.proxyArgs, "--", name)
	proxyArgs = append(proxyArgs, args...)
	return s.proxyCmd, proxyArgs
}

func getTerraformFiles(directory string) ([]string, error) {
	var tfFiles []string
	err := filepath.Walk(directory, func(path string, fileInfo os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !fileInfo.IsDir() && filepath.Ext(path) == ".tf" {
			tfFiles = append(tfFiles, path)
		}
		return nil
	})
	return tfFiles, err
}

func fillTerraformParams(filename string, replacements map[string]string) error {
	fileInfo, err := os.Stat(filename)
	if err != nil {
		return err
	}
	content, err := os.ReadFile(filename)
	if err != nil {
		return err
	}
	fileContent := string(content)

	re := regexp.MustCompile(`%(TFTEST_\w+?)%`)
	replacer := func(match string) string {
		placeholder := match[1 : len(match)-1]
		if value, found := replacements[placeholder]; found {
			return value
		}
		return match
	}

	fileContent = re.ReplaceAllStringFunc(fileContent, replacer)
	return os.WriteFile(filename, []byte(fileContent), fileInfo.Mode())
}
