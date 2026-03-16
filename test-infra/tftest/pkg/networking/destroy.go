package networking

import (
	"fmt"
	"os/exec"

	"k8s.io/test-infra/kubetest/process"
)

// Destroy() cleans up resources created by Setup().
func Destroy(o *Options, control *process.Control) error {
	return deleteFirewalls(o, control)
}

func deleteFirewalls(o *Options, control *process.Control) error {
	firewall := firewallName(o)
	if control.NoOutput(exec.Command("gcloud", "compute", "firewall-rules", "describe", firewall,
		"--project="+o.project,
		"--format=value(name)")) == nil {
		if out, err := exec.Command("gcloud", "compute", "firewall-rules", "delete", firewall,
			"--project="+o.project).CombinedOutput(); err != nil {
			fmt.Printf("command output: %s\n", out)
			return fmt.Errorf("error deleting e2e firewall: %w", err)
		}
	}
	return nil
}
