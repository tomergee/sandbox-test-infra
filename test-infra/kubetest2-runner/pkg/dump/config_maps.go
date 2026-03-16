package dump

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"k8s.io/test-infra/kubetest/util"
)

type gkeConfigMap struct {
	Name      string
	Namespace string
	DataKey   string
}

func DumpConfigMaps(dumpConfigMapsJsonString string) error {
	fmt.Println("⬇️ Dumping config maps...")

	var gkeConfigMaps []gkeConfigMap

	err := json.Unmarshal([]byte(dumpConfigMapsJsonString), &gkeConfigMaps)
	if err != nil {
		return err
	}

	// Fetch any ConfigMap data fields that were requested to be dumped
	var errorMessages []string
	dumpValues := make(map[string]string)
	for _, cm := range gkeConfigMaps {
		cmd := exec.Command("kubectl", "get", fmt.Sprintf("ConfigMaps/%s", cm.Name), "-n", cm.Namespace, "-o", fmt.Sprintf("jsonpath={.data.%s}", cm.DataKey))
		log.Printf("Running: %s", cmd)
		out, err := cmd.Output()
		if err != nil {
			errorMessages = append(errorMessages, util.ExecError(err))
			continue
		}
		jsonKey := strings.Join([]string{cm.Namespace, cm.Name, cm.DataKey}, ".")
		dumpValues[jsonKey] = string(out)
	}
	if len(errorMessages) > 0 {
		return fmt.Errorf("errors while dumping ConfigMaps: %s", strings.Join(errorMessages, ", "))
	}

	jsonDump, err := json.Marshal(dumpValues)
	if err != nil {
		return err
	}

	if err := os.WriteFile(filepath.Join(os.Getenv("ARTIFACTS"), "gke-configmap.json"), jsonDump, 0644); err != nil {
		return err
	}

	return nil
}
