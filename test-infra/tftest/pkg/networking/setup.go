package networking

import (
	"fmt"
	"log"
	"os/exec"
	"regexp"
	"sort"
	"strings"

	"k8s.io/test-infra/kubetest/process"
	"k8s.io/test-infra/kubetest/util"
)

type Options struct {
	project     string
	location    string
	clusterName string
	network     string
}

// poolReTemplate matches instance group URLs of the form `https://www.googleapis.com/compute/v1/projects/some-project/zones/a-zone/instanceGroupManagers/gke-some-cluster-some-pool-90fcb815-grp`. Match meaning:
// m[0]: path starting with zones/
// m[1]: zone
// m[2]: pool name (passed to e2es)
// m[3]: unique hash (used as nonce for firewall rules)
var poolReTemplate = `zones/([^/]+)/instanceGroupManagers/(gke-.*-([0-9a-f]{8})-grp)$`

func NewOptions(project, location, clusterName, network string) *Options {
	return &Options{
		project:     project,
		location:    location,
		clusterName: clusterName,
		network:     network,
	}
}

// Setup() creates networking resources needed to run CL2 test against the cluster.
// Most resources are created via Terraform, however for firewalls we need to extract tags from instance groups.
func Setup(o *Options, control *process.Control) error {
	return setupFirewalls(o, control)
}

func extractPathsFromInstanceGroups(igs string) ([]string, error) {
	igURLs := strings.Split(strings.TrimSpace(igs), ";")
	if len(igURLs) == 0 || len(strings.TrimSpace(igs)) == 0 {
		fmt.Printf("warning: no instance group URLs returned by gcloud, output %q", string(igs))
		return nil, nil
	}
	sort.Strings(igURLs)
	poolRe, err := regexp.Compile(poolReTemplate)
	if err != nil {
		return nil, err
	}
	var instanceGroups []string
	for _, igURL := range igURLs {
		m := poolRe.FindStringSubmatch(igURL)
		if len(m) == 0 {
			return nil, fmt.Errorf("instanceGroupUrl %q did not match regex %v", igURL, poolRe)
		}
		instanceGroups = append(instanceGroups, m[0])
	}
	return instanceGroups, nil
}

func getInstanceGroupsFromGcloud(o *Options) (string, error) {
	igs, err := exec.Command("gcloud", "container", "clusters", "describe", o.clusterName,
		"--format=value(instanceGroupUrls)",
		"--project="+o.project,
		"--zone="+o.location).Output()
	if err != nil {
		out, err2 := exec.Command("gcloud", "container", "clusters", "describe", o.clusterName,
			"--format=value(instanceGroupUrls)",
			"--project="+o.project,
			"--zone="+o.location).CombinedOutput()
		log.Printf("Second attempt output: %s\n", out)
		return "", fmt.Errorf("instance group URL fetch failed: %s %s, err 2: %s", err, out, err2)
	}
	return string(igs), nil
}

func setupFirewalls(o *Options, control *process.Control) error {
	// Configure firewalls
	firewall := firewallName(o)
	if control.NoOutput(exec.Command("gcloud", "compute", "firewall-rules", "describe", firewall,
		"--project="+o.project,
		"--format=value(name)")) == nil {
		// Assume that if this unique firewall exists, it's good to go.
		return nil
	}
	igs, err := getInstanceGroupsFromGcloud(o)
	if err != nil {
		return err
	}
	igsPaths, err := extractPathsFromInstanceGroups(igs)
	if err != nil {
		return err
	}
	tagOut, err := exec.Command("gcloud", "compute", "instances", "list",
		"--project="+o.project,
		"--filter=metadata.created-by ~ "+igsPaths[0],
		"--limit=1",
		"--format=get[delimiter=','](tags.items)").Output()
	if err != nil {
		return fmt.Errorf("instances list failed: %s", util.ExecError(err))
	}
	tag := strings.TrimSpace(string(tagOut))
	if tag == "" {
		return fmt.Errorf("instances list returned no instances (or instance has no tags)")
	}
	ports := "tcp:22,tcp:80,tcp:8080,tcp:9090,tcp:9091,tcp:30000-32767,udp:30000-32767"
	if out, err := exec.Command("gcloud", "compute", "firewall-rules", "create", firewall,
		"--project="+o.project,
		"--network="+o.network,
		"--allow="+ports,
		"--target-tags="+tag).CombinedOutput(); err != nil {
		fmt.Printf("command output: %s\n", out)
		return fmt.Errorf("error creating e2e firewall: %w", err)
	}
	return nil
}
