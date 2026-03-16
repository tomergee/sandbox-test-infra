package process

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Control can commands until a timeout is reached, at which point it signals and then terminates them.
type Control struct {
	termLock    *sync.RWMutex
	terminated  bool
	intLock     *sync.RWMutex
	interrupted bool

	Timeout   time.Duration
	Interrupt *time.Timer
	Terminate *time.Timer

	verbose bool
}

// NewControl constructs a Control with the specified arguments, instiating other necessary fields.
func NewControl(timeout time.Duration, interrupt, terminate *time.Timer, verbose bool) *Control {
	return &Control{
		termLock:    new(sync.RWMutex),
		terminated:  false,
		intLock:     new(sync.RWMutex),
		interrupted: false,
		Timeout:     timeout,
		Interrupt:   interrupt,
		Terminate:   terminate,
		verbose:     verbose,
	}
}

// IsTerminated returns true if the control has been terminated.
func (c *Control) IsTerminated() bool {
	c.termLock.RLock()
	t := c.terminated
	c.termLock.RUnlock()
	return t
}

// IsInterrupted returns true if the control has been interrupted.
func (c *Control) IsInterrupted() bool {
	c.intLock.RLock()
	i := c.interrupted
	c.intLock.RUnlock()
	return i
}

// FinishRunning returns cmd.Wait() and/or times out.
func (c *Control) FinishRunning(cmd *exec.Cmd) error {
	stepName := strings.Join(cmd.Args, " ")
	if c.IsTerminated() {
		return fmt.Errorf("skipped %s (kubetest is terminated)", stepName)
	}
	if cmd.Stdout == nil && c.verbose {
		cmd.Stdout = os.Stdout
	}
	if cmd.Stderr == nil && c.verbose {
		cmd.Stderr = os.Stderr
	}
	log.Printf("Running: %v", stepName)
	defer func(start time.Time) {
		log.Printf("Step '%s' finished in %s", stepName, time.Since(start))
	}(time.Now())

	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("error starting %v: %w", stepName, err)
	}

	finished := make(chan error)

	sigChannel := make(chan os.Signal, 1)
	signal.Notify(sigChannel, os.Interrupt)

	go func() {
		finished <- cmd.Wait()
	}()

	for {
		select {
		case <-sigChannel:
			log.Printf("Killing %v(%v) after receiving signal", stepName, -cmd.Process.Pid)

			pgid := getGroupPid(cmd.Process.Pid)

			if err := syscall.Kill(-pgid, syscall.SIGKILL); err != nil {
				log.Printf("Failed to kill %v: %v", stepName, err)
			}

		case <-c.Terminate.C:
			c.termLock.Lock()
			c.terminated = true
			c.termLock.Unlock()
			c.Terminate.Reset(time.Duration(-1)) // Kill subsequent processes immediately.
			pgid := getGroupPid(cmd.Process.Pid)
			if err := syscall.Kill(-pgid, syscall.SIGKILL); err != nil {
				log.Printf("Failed to kill %v: %v", stepName, err)
			}
			if err := cmd.Process.Kill(); err != nil {
				log.Printf("Failed to terminate %s (terminated 15m after interrupt): %v", stepName, err)
			}
		case <-c.Interrupt.C:
			c.intLock.Lock()
			c.interrupted = true
			c.intLock.Unlock()
			log.Printf("Interrupt after %s timeout during %s. Will terminate in another 15m", c.Timeout, stepName)
			c.Terminate.Reset(15 * time.Minute)
			pgid := getGroupPid(cmd.Process.Pid)
			if err := syscall.Kill(-pgid, syscall.SIGINT); err != nil {
				log.Printf("Failed to interrupt %s. Will terminate immediately: %v", stepName, err)
				syscall.Kill(-pgid, syscall.SIGTERM)
				cmd.Process.Kill()
			}
		case err := <-finished:
			if err != nil {
				var suffix string
				if c.IsTerminated() {
					suffix = " (terminated)"
				} else if c.IsInterrupted() {
					suffix = " (interrupted)"
				}
				return fmt.Errorf("error during %s%s: %w", stepName, suffix, err)
			}
			return err
		}
	}
}

// Output returns cmd.Output(), potentially timing out in the process.
func (c *Control) Output(cmd *exec.Cmd) ([]byte, error) {
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	err := c.FinishRunning(cmd)
	return stdout.Bytes(), err
}

// getGroupPid gets the process group to kill the entire main/child process
// if Getpgid return error use the current process Pid
func getGroupPid(pid int) int {
	pgid, err := syscall.Getpgid(pid)
	if err != nil {
		log.Printf("Failed to get the group process from %v: %v", pid, err)
		return pid
	}
	return pgid
}
