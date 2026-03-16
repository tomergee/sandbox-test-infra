package main

import (
	"flag"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"time"

	"github.com/spf13/pflag"
	"k8s.io/test-infra/kubetest/process"
	k8sutil "k8s.io/test-infra/kubetest/util"

	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/boskos"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/config"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/env"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/kubectl"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/networking"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/stepexecutor"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/terraform"
	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/util"
)

var (
	interrupt = time.NewTimer(time.Duration(0)) // interrupt testing at this time.
	terminate = time.NewTimer(time.Duration(0)) // terminate testing at this time.

	suite = k8sutil.TestSuite{Name: "tftest"}
)

func defineFlags() *config.TftestOptions {
	o := config.TftestOptions{}
	extractStrategy := env.ExtractStrategy{}
	o.Extract = &extractStrategy

	flag.DurationVar(&o.Timeout, "timeout", time.Duration(0), "Terminate testing after the timeout duration (s/m/h).")

	// Parameters for setting up basic cluster
	flag.StringVar(&o.ClusterName, "cluster", "", "Name of the GKE cluster to provision.")
	flag.DurationVar(&o.BoskosWaitDuration, "boskos-wait-duration", 1*time.Hour, "Defines how long it waits until quit getting Boskos resoure, default 1 hour")
	flag.StringVar(&o.BoskosPool, "gcp-project-type", "", "Boskos pool to borrow a GCP project from. Mutually exclusive with --gcp-project.")
	flag.StringVar(&o.Project, "gcp-project", "", "GCP project to use for the test. Mutually exclusive with --gcp-project-type.")
	flag.StringVar(&o.Location, "location", "", "Location of the GKE cluster to provision. Needed to run test command against the cluster.")
	flag.IntVar(&o.Parallelism, "parallelism", 10, "Parallelism of operations performed by Terraform when provisioning/destroying a cluster (default: 10).")
	flag.StringVar(&o.NodePoolName, "node-pool-name", "node-pools", "Terraform resource name for the node pools that will be removed from terraform state before destroy.")
	flag.IntVar(&o.ApplyRetries, "apply-retries", 3, "Retry attempts performed by Terraform when provisioning a cluster (default: 3).")
	flag.DurationVar(&o.ApplyTimeout, "apply-timeout", time.Duration(1*time.Hour), "Defines timeout for cluster provisioning duration (default: 1 hour).")
	flag.DurationVar(&o.DestroyTimeout, "destroy-timeout", time.Duration(1*time.Hour), "Defines timeout for cluster destruction duration (default: 1 hour).")
	flag.StringVar(&o.MetadataSources, "metadata-sources", "images.json", "Comma-separated list of files inside ./artifacts to merge into metadata.json")
	flag.BoolVar(&o.Down, "down", true, "Defines whether the cluster should be destroyed when the scenario finishes. In case of errors, the cluster will be destroyed regardless.")
	flag.BoolVar(&o.Up, "up", true, "Defines whether to create cluster and perform initial resource cleaning.")
	flag.StringVar(&o.TfScenario, "tf-scenario", "", "Path to the directory containing the Terraform scenario.")
	flag.StringVar(&o.Network, "network", "default", "Network used by cluster (for firewall config).")

	// env.ExtractStrategy implments the flag.Value interface and when the flag
	// is provided *ExtractStrategy::Set() is called with the flag's value.
	flag.Var(&extractStrategy, "extract", "Get the GKE version from the specified release")

	// Parameters for running test
	flag.StringVar(&o.TestOptions.Cmd, "test-cmd", "", "Command to run against the cluster.")
	flag.StringVar(&o.TestOptions.CmdName, "test-cmd-name", "", "name to log the test command as in xml results")
	// Use pflag as go flag doesn't support StringArrayVar
	pflag.StringArrayVar(&o.TestOptions.CmdArgs, "test-cmd-args", []string{}, "Arguments for test-cmd")
	pflag.StringArrayVar(&o.EnvVars, "env", []string{}, "Environment variables to set before running test")

	// proxy command
	flag.StringVar(&o.ProxyCmd, "proxy-cmd", "", "Proxy command to wrap Terraform apply commands. When set, Terraform commands become '<proxy-cmd> <proxy-cmd-args> -- terraform <terraform-args>'")
	pflag.StringArrayVar(&o.ProxyArgs, "proxy-cmd-args", []string{}, "Arguments for 'proxy-cmd'")

	// For dumping cluster config
	flag.StringVar(&o.PreTestCmd, "pre-test-cmd", "", "If set, run the provided command before running any tests.")
	flag.StringVar(&o.PostTestCmd, "post-test-cmd", "", "If set, run the provided command after running all the tests.")
	return &o
}

func run(o *config.TftestOptions) error {
	if !terminate.Stop() {
		<-terminate.C
	}
	if !interrupt.Stop() {
		<-interrupt.C
	}
	control := process.NewControl(o.Timeout, interrupt, terminate, true)
	se := stepexecutor.NewStepExecutor(control, &suite, o.PreTestCmd, o.PostTestCmd)
	if o.Timeout > 0 {
		log.Printf("Limiting testing to %s", o.Timeout)
		interrupt.Reset(o.Timeout)
	}
	defer util.WriteMetadata(control, os.Getenv("ARTIFACTS"), o.MetadataSources)
	defer control.WriteXML(&suite, os.Getenv("ARTIFACTS"), time.Now())
	defer se.TryPostTestCmd()

	if err := control.XMLWrap(&suite, "Prepare project", func() error { return boskos.PrepareProject(o) }); err != nil {
		log.Printf("Failed to prepare a GCP project: %v", err)
		return err
	}

	if err := env.Setup(o, control); err != nil {
		log.Printf("Failed to initialize env.Setup: %v", err)
		return err
	}

	s := &terraform.Scenario{}
	if err := control.XMLWrap(&suite, "Initialize Terraform scenario", func() error { return terraform.InitTerraform(s, o, control) }); err != nil {
		log.Printf("Failed to initialize Terraform: %v", err)
		return err
	}

	interruptChan := make(chan os.Signal, 1)
	signal.Notify(interruptChan, os.Interrupt)
	go func() {
		for range interruptChan {
			log.Print("Captured ^C, attempting to clean up resources..")
			if err := cleanup(s, o, control); err != nil {
				log.Printf("Error cleaning up resources: %v", err)
			}
			os.Exit(2)
		}
	}()

	if o.Down {
		defer cleanup(s, o, control)
	}

	if o.Up {
		if err := control.XMLWrap(&suite, "Apply Terraform scenario", func() error { return s.Apply(o.ApplyTimeout) }); err != nil {
			log.Printf("Failed to apply Terraform scenario: %v", err)
			return err
		}
	}

	if err := kubectl.Setup(o); err != nil {
		log.Printf("Failed setting up kubectl: %v", err)
		return err
	}

	if err := se.TryPreTestCmd(); err != nil {
		log.Printf("Failed running pre-test-cmd: %v", err)
		return err
	}

	// Run test command if there's one.
	// Currently we set up the environment assuming the test will run clusterloader2 with some flavor of load scenario.
	// For other configurations, this may need to be adjusted.
	// In particular, for running OSS correctness suite we'll need to set up bastion SSH (see kubetest implementation for reference).
	if o.TestOptions.Cmd != "" {
		if err := networking.Setup(networking.NewOptions(o.Project, o.Location, o.ClusterName, o.Network), control); err != nil {
			log.Printf("Failed setting up networking: %v", err)
			return err
		}

		if err := control.XMLWrap(&suite, o.TestOptions.CmdName, func() error {
			// Run test command (usually CL2)
			cmdLine := os.ExpandEnv(o.TestOptions.Cmd)
			return control.FinishRunning(exec.Command(cmdLine, o.TestOptions.CmdArgs...))
		}); err != nil {
			log.Printf("Failed to run test scenario against the cluster: %v", err)
			return err
		}
	}
	return nil
}

func cleanup(scenario *terraform.Scenario, o *config.TftestOptions, c *process.Control) error {
	log.Print("Attempting to clean up resources that may have been created...")
	if err := c.XMLWrap(&suite, "Clean up network resources", func() error {
		return networking.Destroy(networking.NewOptions(o.Project, o.Location, o.ClusterName, o.Network), c)
	}); err != nil {
		log.Printf("Error, failed to cleanup network resources: %v", err)
	}

	if scenario == nil {
		log.Print("Scenario to cleanup is nil. Skipping terraform destroy step.")
		return nil
	}
	if err := c.XMLWrap(&suite, "Destroy Terraform scenario", func() error { return scenario.Destroy(o.DestroyTimeout) }); err != nil {
		log.Printf("Error, terraform destroy step failed: %v", err)
	}
	return nil
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	pflag.CommandLine = pflag.NewFlagSet(os.Args[0], pflag.ContinueOnError)

	o := defineFlags()

	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)
	if err := pflag.CommandLine.Parse(os.Args[1:]); err != nil {
		log.Fatalf("Flag parse failed: %v", err)
	}
	if err := o.ValidateFlags(); err != nil {
		log.Fatalf("Flag validation error: %v", err)
	}

	if err := run(o); err != nil {
		if boskos.HasResource() {
			if berr := boskos.ReleaseResources(); berr != nil {
				log.Fatalf("ERROR: Failed to release Boskos resources: %v (tftest error: %v)", berr, err)
			}
		}
		log.Fatalf("Something went wrong: %v", err)
	}
}
