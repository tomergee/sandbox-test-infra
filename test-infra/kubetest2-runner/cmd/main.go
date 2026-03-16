package main

import (
	"fmt"
	"log"
	"os/exec"
	"time"

	flag "github.com/spf13/pflag"

	"gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/pkg/config"
	"gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/pkg/dump"
	"gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/pkg/env"
	gproxysetup "gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/pkg/gproxy-setup"
	"gke-internal.googlesource.com/test-infra/perf-tests/kubetest2-runner/pkg/process"
)

var (
	interrupt = time.NewTimer(time.Duration(0)) // interrupt testing at this time.
	terminate = time.NewTimer(time.Duration(0)) // terminate testing at this time.
	opts      = &config.Kubetest2RunnerOptions{}
)

func initFlags() {
	flag.DurationVar(&opts.Timeout, "timeout", time.Duration(0), "Terminate testing after the timeout duration (s/m/h).")

	flag.StringVar(&opts.PreTestCmd, "pre-test-cmd", "", "If set, run the provided command before running any tests.")
	flag.StringVar(&opts.PostTestCmd, "post-test-cmd", "", "If set, run the provided command after running all the tests.")
	flag.StringArrayVar(&opts.GproxyPatches, "gproxy-patches", []string{}, "List of patches to apply to the CreateClusterRequest using gproxy")
	flag.StringVar(&opts.DumpConfigMaps, "dump-configmaps", "[]", "A JSON description of ConfigMaps to dump as part of gathering cluster logs.")
	flag.StringArrayVar(&opts.Env, "env", []string{}, "Job specific environment setting")

	flag.StringVar(&opts.Kubetest2Deployer, "kubetest2-deployer", "", "kubetest2 deployer (see https://github.com/kubernetes-sigs/kubetest2?tab=readme-ov-file#reference-implementations for available options)")
	flag.StringVar(&opts.Kubetest2DeployerArgs, "kubetest2-deployer-args", "", "kubetest2 deployer arguments")
	flag.StringVar(&opts.Kubetest2Tester, "kubetest2-tester", "", "kubetest2 tester (see https://github.com/kubernetes-sigs/kubetest2?tab=readme-ov-file#reference-implementations for available options)")
	flag.StringVar(&opts.Kubetest2TesterArgs, "kubetest2-tester-args", "", "kubetest2 tester arguments")
}

func parseOptions() {
	flag.Parse()
}

func run(opts *config.Kubetest2RunnerOptions) (result error) {
	if !terminate.Stop() {
		<-terminate.C
	}
	if !interrupt.Stop() {
		<-interrupt.C
	}
	control := process.NewControl(opts.Timeout, interrupt, terminate, true)
	if opts.Timeout > 0 {
		log.Printf("Limiting testing to %s", opts.Timeout)
		interrupt.Reset(opts.Timeout)
	}

	if len(opts.GproxyPatches) > 0 {
		gproxysetup.SetupGproxy()
	}

	kubetest2Args := []string{}

	kubetest2Args = append(kubetest2Args, opts.Kubetest2Deployer)
	kubetest2Args = append(kubetest2Args, "--up")
	kubetest2Args = append(kubetest2Args, "--down")
	kubetest2Args = append(kubetest2Args, fmt.Sprintf("--post-test-cmd=%s", opts.PostTestCmd))
	kubetest2Args = append(kubetest2Args, fmt.Sprintf("--pre-test-cmd=%s", opts.PreTestCmd))

	deployerArgs, err := opts.CreateDeployerArgsSlice()
	if err != nil {
		return err
	}
	kubetest2Args = append(kubetest2Args, deployerArgs...)

	kubetest2Args = append(kubetest2Args, fmt.Sprintf("--test=%s", opts.Kubetest2Tester))
	kubetest2Args = append(kubetest2Args, "--")

	testerArgs, err := opts.CreateTesterArgsSlice()
	if err != nil {
		return err
	}
	kubetest2Args = append(kubetest2Args, testerArgs...)

	cmd := exec.Command("kubetest2", kubetest2Args...)
	cmd.Env = env.CreateCmdEnv(opts.Env)
	if len(opts.GproxyPatches) > 0 {
		gproxysetup.SetupGproxyCommand(cmd, opts.GproxyPatches)
	}

	if err := control.FinishRunning(cmd); err != nil {
		return err
	}

	if err := dump.DumpConfigMaps(opts.DumpConfigMaps); err != nil {
		log.Printf("Failed to dump configmaps: %v\n", err)
	}

	return nil
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	initFlags()
	parseOptions()
	if err := opts.ValidateFlags(); err != nil {
		log.Fatalf("Flag validation error: %v", err)
	}

	if err := run(opts); err != nil {
		log.Fatalf("Something went wrong: %v", err)
	}
}
