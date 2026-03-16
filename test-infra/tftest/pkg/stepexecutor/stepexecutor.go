package stepexecutor

import (
	"log"
	"os"
	"os/exec"
	"strings"

	"k8s.io/test-infra/kubetest/process"
	"k8s.io/test-infra/kubetest/util"
)

// StepExecutor is a wrapper for common commands
type StepExecutor struct {
	control     *process.Control
	suite       *util.TestSuite
	preTestCmd  string
	postTestCmd string
}

// NewStepExecutor returns new StepExecutor
func NewStepExecutor(control *process.Control, suite *util.TestSuite, preTestCmd, postTestCmd string) *StepExecutor {
	return &StepExecutor{control, suite, preTestCmd, postTestCmd}
}

// TryPreTestCmd is a wrapper for running pre-test command, and skip if there is none
func (se *StepExecutor) TryPreTestCmd() error {
	if se.preTestCmd != "" {
		return se.tryCmd("pre-test-cmd", se.preTestCmd)
	}
	return nil
}

// TryPostTestCmd is a wrapper for running post-test command, and skip if there is none
func (se *StepExecutor) TryPostTestCmd() error {
	if se.postTestCmd != "" {
		return se.tryCmd("post-test-cmd", se.postTestCmd)
	}
	return nil
}

func (se *StepExecutor) tryCmd(name, command string) error {
	log.Printf("Running step %s with command %s", name, command)
	return se.control.XMLWrap(se.suite, name, func() error {
		cmdLineTokenized := strings.Fields(os.ExpandEnv(command))
		return se.control.FinishRunning(exec.Command(cmdLineTokenized[0], cmdLineTokenized[1:]...))
	})
}
