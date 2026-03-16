package config

import (
	"fmt"
	"time"

	"k8s.io/test-infra/kubetest/process"
)

type ExtractStrategy interface {
	String() string
	Enabled() bool
	Set(string) error
	GetVersion(string, string, *process.Control) (string, error)
}

type TftestOptions struct {
	ClusterName        string
	Location           string
	Project            string
	BoskosPool         string
	BoskosWaitDuration time.Duration
	Network            string
	NodePoolName       string
	Parallelism        int
	ApplyRetries       int
	MetadataSources    string
	Timeout            time.Duration
	ApplyTimeout       time.Duration
	DestroyTimeout     time.Duration
	Down               bool
	Up                 bool
	TfScenario         string
	TestOptions        TestOptions
	ProxyCmd           string
	ProxyArgs          []string
	PreTestCmd         string
	PostTestCmd        string
	Extract            ExtractStrategy
	EnvVars            []string
}

type TestOptions struct {
	Cmd     string
	CmdArgs []string
	CmdName string
}

func (o *TftestOptions) ValidateFlags() error {
	if len(o.Project) > 0 && len(o.BoskosPool) > 0 {
		return fmt.Errorf("cannot set --project and --boskos-pool simultaneously")
	}
	if len(o.Location) > 0 && o.BoskosPool == "gke-scalability-65k-project" {
		return fmt.Errorf("cannot set --location and --boskos-pool simultaneously. Location will be chosen automatically based on chosen project")
	}
	if len(o.Project) == 0 && len(o.BoskosPool) == 0 {
		return fmt.Errorf("either --project or --boskos-pool must be set")
	}
	if !o.Up && o.Down {
		return fmt.Errorf("--up=false and --down=true is not supported currently, as terraform cannot destroy without a state file")
	}
	return nil
}
