package env

import (
	"fmt"
	"log"
	"os"
	"strings"

	"k8s.io/test-infra/kubetest/process"

	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/config"
)

const (
	// CL2_PROJECT is used for CL2 test config
	CL2_PROJECT = "CL2_PROJECT"
	// PROJECT is used by run e2e scripts and pre-test
	PROJECT = "PROJECT"
	// REGION is used by pre-test
	REGION = "REGION"
	// ZONE is used by pre-test
	ZONE = "ZONE"
	// CLUSTER_NAME is used by pre-test
	CLUSTER_NAME = "CLUSTER_NAME"
	// CLUSTER_API_VERSION is used to set upgrade version
	CLUSTER_API_VERSION = "CLUSTER_API_VERSION"
	// TFTEST_MIN_MASTER_VERSION is used to set the min master version in .tf files
	TFTEST_MIN_MASTER_VERSION = "TFTEST_MIN_MASTER_VERSION"
	// TFTEST_LOCATION is used to set the location values in .tf files
	TFTEST_LOCATION = "TFTEST_LOCATION"
	// TFTEST_NODE_LOCATIONS is used for specifing zones
	TFTEST_NODE_LOCATIONS = "TFTEST_NODE_LOCATIONS"
	// TFTEST_REGION is used to set the region values in .tf files
	TFTEST_REGION = "TFTEST_REGION"
	// TFTEST_RESOURCE_CREATE_TIMEOUT is used to specify per resource create timeout.
	TFTEST_RESOURCE_CREATE_TIMEOUT = "TFTEST_RESOURCE_CREATE_TIMEOUT"
	// TFTEST_RESOURCE_DELETE_TIMEOUT is used to specify per resource destroy timeout.
	TFTEST_RESOURCE_DELETE_TIMEOUT = "TFTEST_RESOURCE_DELETE_TIMEOUT"
	// AUTH_NETWORK_ADDR is an env variable that contains the list of CIDRs for the
	// master authorized networks
	AUTH_NETWORK_ADDR = "AUTH_NETWORK_ADDR"
	// TFTEST_AUTH_NETWORK_ADDR is used to specify the master authorized networks in .tf files
	TFTEST_AUTH_NETWORK_ADDR = "TFTEST_AUTH_NETWORK_ADDR"
	// MASTER_AUTH_NETWORK_CONFIG_CIDR_BLOCK is the template for the .tf files for each
	// authorized network CIDR
	MASTER_AUTH_NETWORK_CONFIG_CIDR_BLOCK = `cidr_blocks { cidr_block = "%s" }`
)

var defaultVars = map[string]string{
	"USE_GKE_GCLOUD_AUTH_PLUGIN": "True",
	// TODO: make env configurable
	"CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER": "https://staging-container.sandbox.googleapis.com/",
	// For gproxy to work with terraform we need to set the GKE custom endpoint via
	// this environment variable as gproxy overwrites this variable to redirect the
	// calls to itself. When the enpoint is set in the "provider" block in the .tf
	// files this env variable is ignored, so that gproxy can't intercept the calls.
	"GOOGLE_CONTAINER_CUSTOM_ENDPOINT": "https://staging-container.sandbox.googleapis.com/",
	TFTEST_RESOURCE_CREATE_TIMEOUT:     "40m",
	TFTEST_RESOURCE_DELETE_TIMEOUT:     "40m",
}

// Setup() sets the environment variables for running a CL2 test scenario.
func Setup(o *config.TftestOptions, control *process.Control) error {
	vMap, err := parseEnvVars(o.EnvVars)
	if err != nil {
		log.Printf("errors parsing env variables, not setting: %v", err)
	}

	defaultVars[CL2_PROJECT] = o.Project
	defaultVars[PROJECT] = o.Project
	defaultVars[CLUSTER_NAME] = o.ClusterName
	defaultVars[TFTEST_LOCATION] = o.Location
	if o.BoskosPool == "gke-scalability-65k-project" {
		if o.Project == "gke-scalability-megacluster" {
			defaultVars[TFTEST_NODE_LOCATIONS] = `["us-central1-a", "us-central1-b", "us-central1-c"]`
		} else if o.Project == "gke-scalability-cluster-65k-1" {
			defaultVars[TFTEST_NODE_LOCATIONS] = `["us-east1-b", "us-east1-c", "us-east1-d"]`
		}
	}

	defaultVars[TFTEST_AUTH_NETWORK_ADDR] = prepareAuthorizedNetworks()

	locationSplit := strings.Split(o.Location, "-")

	if len(locationSplit) < 2 || len(locationSplit) > 3 {
		return fmt.Errorf("Unsupported location %s, cannot parse to zone or region", o.Location)
	}
	region := fmt.Sprintf("%s-%s", locationSplit[0], locationSplit[1])
	defaultVars[TFTEST_REGION] = region
	if len(locationSplit) == 2 {
		defaultVars[REGION] = o.Location
	}
	if len(locationSplit) == 3 {
		defaultVars[ZONE] = o.Location
	}
	vMap = applyDefaults(vMap, defaultVars)
	setEnvVars(vMap)

	if o.Extract.Enabled() {
		version, err := o.Extract.GetVersion(o.Project, o.Location, control)
		if err != nil {
			log.Printf("Failed to get version from '--extract' value: %v: %v", o.Extract.String(), err)
			return err
		}
		setEnvVars(map[string]string{
			CLUSTER_API_VERSION:       version,
			TFTEST_MIN_MASTER_VERSION: version,
		})
	}
	return nil
}

func applyDefaults(vars, defaults map[string]string) map[string]string {
	for k, v := range defaults {
		if val, ok := vars[k]; !ok {
			vars[k] = v
		} else {
			log.Printf("Using %s override: %s", k, val)
		}
	}
	return vars
}

func parseEnvVars(vars []string) (map[string]string, error) {
	m := map[string]string{}
	errs := []error{}
	for _, v := range vars {
		parts := strings.SplitN(v, "=", 2)
		// Value can be set to empty string, but var name can't be empty.
		if len(parts) != 2 || len(parts[0]) == 0 {
			errs = append(errs, fmt.Errorf("failed to parse env var %s, expecting '<name>=<value>' format", v))
		}
		m[parts[0]] = parts[1]
	}
	if len(errs) != 0 {
		return m, fmt.Errorf("%v", errs)
	}
	return m, nil
}

func setEnvVars(vMap map[string]string) {
	for k, v := range vMap {
		os.Setenv(k, v)
	}
}

func prepareAuthorizedNetworks() string {
	authNetworkAddress := os.Getenv("AUTH_NETWORK_ADDR")
	if authNetworkAddress == "" {
		return ""
	}
	authNetworks := strings.Split(authNetworkAddress, ",")
	cidrBlocks := []string{}
	for _, network := range authNetworks {
		cidrBlocks = append(cidrBlocks, fmt.Sprintf(MASTER_AUTH_NETWORK_CONFIG_CIDR_BLOCK, network))
	}
	return strings.Join(cidrBlocks, "\n")
}
