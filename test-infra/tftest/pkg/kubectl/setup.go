package kubectl

import (
	"log"
	"os"
	"os/exec"
	"time"

	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/config"
)

// Setup() configures kubectl to reach the test cluster.
func Setup(o *config.TftestOptions) error {
	f, err := os.CreateTemp("", "gke-kubecfg")
	if err != nil {
		return err
	}
	kubecfg := f.Name()
	if err := f.Chmod(0600); err != nil {
		return err
	}
	f.Close()

	if err := os.Setenv("KUBECONFIG", kubecfg); err != nil {
		return err
	}

	// Get cluster credentials.
	getCredentialsCmd := exec.Command("gcloud", "container", "clusters", "get-credentials", o.ClusterName, "--project", o.Project, "--zone", o.Location)
	getCredentialsCmd.Env = os.Environ()
	out, err := getCredentialsCmd.CombinedOutput()
	log.Printf("Get credentials command output: %s\n", out)
	if err != nil {
		return err
	}

	// Test kubectl
	for i := 0; i < 5; i++ {
		if i > 0 {
			// Wait a minute and attempt to try again.
			log.Printf("Waiting 1m before retyring")
			time.Sleep(1 * time.Minute)
		}
		testKubectl := exec.Command("kubectl", "get", "ns")
		testKubectl.Env = os.Environ()
		out, err = exec.Command("kubectl", "get", "ns").CombinedOutput()
		if err == nil {
			log.Printf("kubectl get ns output: %s\n", out)
			return nil
		}
		log.Printf("Error in kubectl execution: %v", err)
		log.Printf("kubectl get ns output: %s\n", out)
	}
	return err
}
