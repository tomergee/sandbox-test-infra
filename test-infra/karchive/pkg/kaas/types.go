package kaas

import (
	"time"
)

// RunInfo stores all pieces of information about the Prow job run that are necessary to create debug links.
type RunInfo struct {
	*JobInfo
	*ClusterInfo
}

// Run-related data accessible from within the test pod container.
type JobInfo struct {
	// JobStartTimestamp is the timestamp corresponding to the Prow job's start.
	JobStartTimestamp time.Time `json:"job_start_timestamp"`

	// JobFinishTimestamp is the upper bound timestamp for the Prow job's finish.
	JobFinishTimestamp time.Time `json:"job_finish_timestamp"`

	// Environment corresponds to the GKE environment of the cluster.
	Environment string `json:"environment"`

	// IsSandbox tells whether the test cluster was created in a sandbox environment.
	IsSandbox bool `json:"is_sandbox"`

	// ClusterVersion is the actual GKE patch version of the cluster.
	ClusterVersion string `json:"cluster_version"`
}

// Run-related data accessible from the mastertest-data configmap.
// See http://google3/cloud/kubernetes/distro/components/mastertest
// for more details.
type ClusterInfo struct {
	// ProjectID is the name of cluster's project.
	ProjectID string `json:"project_id"`

	// ProjectNumber is the number of cluster's project.
	ProjectNumber string `json:"project_number"`

	// Location is the zone/region of the cluster.
	Location string `json:"location"`

	// Name is the name of the cluster.
	Name string `json:"name"`

	// Hash is the hash of the cluster.
	Hash string `json:"hash"`

	// MasterProjectID is the name of the cluster's HMP project.
	MasterProjectID string `json:"master_project_id"`

	// MasterProjectNumber is the number of the cluster's HMP project.
	MasterProjectNumber string `json:"master_project_number"`

	// MasterResources represents the info about the masters.
	MasterResources []*MasterResource `json:"master_resources"`

	// ComponentVersions represents versions of gke components on cluster
	ComponentsVersions map[string]string `json:"component_versions"`

	// ComponentsVersionsHash is a hash of clusters selected_components
	ComponentsVersionsHash string `json:"components_versions_hash"`
}

// MasterResource represents info about a single GKE master machine.
type MasterResource struct {
	// Name of the master VM.
	Name string `json:"name"`

	// ID of the master VM.
	ID string `json:"id"`

	// InstanceID represents the GCE instance ID of the master VM.
	InstanceID string `json:"instance_id"`

	// Zone where the master VM lies in.
	Zone string `json:"zone"`

	// IPAddress is the IP address of the master VM.
	IPAddress string `json:"ip_address"`

	// InternalIPAddress is the internal IP address of the master VM.
	InternalIPAddress string `json:"-"`

	// Project is the name of the HMP project where the master VM lies in.
	Project string `json:"-"`

	// EtcdIPAddress is the IP address of master's etcd replica.
	EtcdIPAddress string `json:"etcd_ip_address"`
}
