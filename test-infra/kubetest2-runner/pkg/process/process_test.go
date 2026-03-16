package process

import (
	"log"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestOutput(t *testing.T) {
	cases := []struct {
		name              string
		terminated        bool
		interrupted       bool
		causeTermination  bool
		causeInterruption bool
		pass              bool
		sleep             int
		output            bool
		shouldError       bool
		shouldInterrupt   bool
		shouldTerminate   bool
	}{
		{
			name: "finishRunning can pass",
			pass: true,
		},
		{
			name:   "output can pass",
			output: true,
			pass:   true,
		},
		{
			name:        "finishRuning can fail",
			pass:        false,
			shouldError: true,
		},
		{
			name:        "output can fail",
			pass:        false,
			output:      true,
			shouldError: true,
		},
		{
			name:        "finishRunning should error when terminated",
			terminated:  true,
			pass:        true,
			shouldError: true,
		},
		{
			name:        "output should error when terminated",
			terminated:  true,
			pass:        true,
			output:      true,
			shouldError: true,
		},
		{
			name:              "finishRunning should interrupt when interrupted",
			pass:              true,
			sleep:             60,
			causeInterruption: true,
			shouldError:       true,
		},
		{
			name:              "output should interrupt when interrupted",
			pass:              true,
			sleep:             60,
			output:            true,
			causeInterruption: true,
			shouldError:       true,
		},
		{
			name:             "output should terminate when terminated",
			pass:             true,
			sleep:            60,
			output:           true,
			causeTermination: true,
			shouldError:      true,
		},
		{
			name:             "finishRunning should terminate when terminated",
			pass:             true,
			sleep:            60,
			causeTermination: true,
			shouldError:      true,
		},
	}

	clearTimers := func(c *Control) {
		if !c.Terminate.Stop() {
			<-c.Terminate.C
		}
		if !c.Interrupt.Stop() {
			<-c.Interrupt.C
		}
	}

	for _, tc := range cases {
		log.Println(tc.name)
		interrupt := time.NewTimer(time.Duration(0))
		terminate := time.NewTimer(time.Duration(0))
		c := NewControl(time.Duration(0), interrupt, terminate, false)
		c.terminated = tc.terminated
		c.interrupted = tc.interrupted
		clearTimers(c)
		if tc.causeInterruption {
			interrupt.Reset(0)
		}
		if tc.causeTermination {
			terminate.Reset(0)
		}
		var cmd *exec.Cmd
		if !tc.pass {
			cmd = exec.Command("false")
		} else if tc.sleep == 0 {
			cmd = exec.Command("true")
		} else {
			cmd = exec.Command("sleep", strconv.Itoa(tc.sleep))
		}
		var err error
		if tc.output {
			_, err = c.Output(cmd)
		} else {
			err = c.FinishRunning(cmd)
		}
		if err == nil == tc.shouldError {
			t.Errorf("Step %s shouldError=%v error: %v", tc.name, tc.shouldError, err)
		}
		if tc.causeInterruption && !c.interrupted {
			t.Errorf("Step %s did not interrupt, err: %v", tc.name, err)
		} else if tc.causeInterruption && !terminate.Reset(0) {
			t.Errorf("Step %s did not reset the terminate timer: %v", tc.name, err)
		}
		if tc.causeTermination && !c.terminated {
			t.Errorf("Step %s did not terminate, err: %v", tc.name, err)
		}
	}
}

func TestOutputOutputs(t *testing.T) {
	interrupt := time.NewTimer(time.Duration(1) * time.Second)
	terminate := time.NewTimer(time.Duration(1) * time.Second)
	c := NewControl(time.Duration(1)*time.Second, interrupt, terminate, false)

	b, err := c.Output(exec.Command("echo", "hello world"))
	txt := string(b)
	if err != nil {
		t.Fatalf("failed to echo: %v", err)
	}
	if !strings.Contains(txt, "hello world") {
		t.Errorf("output() did not echo hello world: %v", txt)
	}
}
