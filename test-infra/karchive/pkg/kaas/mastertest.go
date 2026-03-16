package kaas

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"crypto/md5"
	"encoding/hex"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	_ "k8s.io/client-go/plugin/pkg/client/auth/gcp"
	"k8s.io/client-go/tools/clientcmd"
)

// Provides data accessible from the mastertest component.
func getClusterInfo() (*ClusterInfo, error) {
	data, err := getConfigMapData("mastertest-data")
	if err != nil {
		return nil, err
	}
	clusterInfo := map[string]string{}
	if err := json.Unmarshal([]byte(data["clusterInfo"]), &clusterInfo); err != nil {
		return nil, fmt.Errorf("problem with JSON conversion: %w", err)
	}

	masterResources, err := getMasterResources()
	if err != nil {
		return nil, err
	}

	componentsVersions := map[string]string{}
	if err := json.Unmarshal([]byte(data["componentsVersions"]), &componentsVersions); err != nil {
		return nil, fmt.Errorf("problem with JSON conversion: %w", err)
	}

	// clusterInfo["masterProjectId"] is empty due to the relevant Spanner field
	// not being filled on cluster creation. Because of that, we check for the
	// project where master VMs lie in.
	// TODO(b/134998312): remove this workaround once b/134998312 is fixed.
	masterProjectID := clusterInfo["masterProjectId"]
	if masterProjectID == "" {
		for _, mr := range masterResources {
			if mr.Project != "" {
				masterProjectID = mr.Project
				break
			}
		}
	}

	// componentsVersions is a JSON representing cluster's selected_components
	// where keys are names and values are version of components
	// the map is sorted by key (json.Marshal was used)
	componentsVersionsHash := ""
	if componentsVersions, ok := clusterInfo["componentsVersions"]; ok {
		hasher := md5.Sum([]byte(componentsVersions))
		componentsVersionsHash = hex.EncodeToString(hasher[:])
	}

	return &ClusterInfo{
		Hash:                   clusterInfo["Hash"],
		Name:                   clusterInfo["Name"],
		Location:               clusterInfo["Location"],
		ProjectID:              clusterInfo["ProjectName"],
		ProjectNumber:          clusterInfo["ProjectNumber"],
		MasterProjectID:        masterProjectID,
		MasterProjectNumber:    clusterInfo["MasterProjectNumber"],
		MasterResources:        masterResources,
		ComponentsVersions:     componentsVersions,
		ComponentsVersionsHash: componentsVersionsHash,
	}, nil
}

// Get and transform the mastertest-config ConfigMap contents.
func getMasterResources() ([]*MasterResource, error) {
	result := []*MasterResource{}
	data, err := getConfigMapData("mastertest-config")
	if err != nil {
		return nil, err
	}
	for k, v := range data {
		masterInfo := map[string]string{}
		if !strings.HasPrefix(k, "gke-") {
			continue
		}
		if err := json.Unmarshal([]byte(v), &masterInfo); err != nil {
			return nil, fmt.Errorf("problem with JSON conversion: %w", err)
		}
		result = append(result, createMasterResource(masterInfo))
	}
	return result, nil
}

func createMasterResource(master map[string]string) *MasterResource {
	return &MasterResource{
		Name:              master["name"],
		ID:                master["master_id"],
		InstanceID:        master["id"],
		Zone:              master["zone"],
		IPAddress:         master["external_ip"],
		InternalIPAddress: master["internal_ip"],
		Project:           master["project"],
		EtcdIPAddress:     ipAliasToEtcdIpAddress(master["ip_aliases"]),
	}
}

// Parses the CIDR with /32 mask to the IP address of master's etcd instance.
// TODO(b/195505979): clean this up.
func ipAliasToEtcdIpAddress(ipAlias string) string {
	etcdIpAddress := ""
	if index := strings.Index(ipAlias, "/32"); index > 0 {
		etcdIpAddress = ipAlias[:index]
	}
	return etcdIpAddress
}

// Returns a specific ConfigMap's .data field contents.
// It assumes the ConfigMap is inside the kube-system namespace.
func getConfigMapData(name string) (map[string]string, error) {
	config, err := clientcmd.BuildConfigFromFlags("", os.Getenv("KUBECONFIG"))
	if err != nil {
		return nil, err
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}
	configmap, err := clientset.CoreV1().ConfigMaps("kube-system").Get(context.Background(), name, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("cannot get the %s configmap: %w", name, err)
	}
	return configmap.Data, nil
}
