package util

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"k8s.io/test-infra/kubetest/process"
)

// maybeMergeMetadata will add new keyvals into the map; quietly eats errors.
func MaybeMergeJSON(meta map[string]string, path string) {
	if data, err := os.ReadFile(path); err == nil {
		json.Unmarshal(data, &meta)
	}
}

// Write metadata.json, including version and env arg data.
func WriteMetadata(control *process.Control, path, metadataSources string) error {
	m := make(map[string]string)

	// Look for any sources of metadata and load 'em
	for _, f := range strings.Split(metadataSources, ",") {
		MaybeMergeJSON(m, filepath.Join(path, f))
	}

	// version value has been set during env.Setup
	ver := os.Getenv("CLUSTER_API_VERSION")
	m["job-version"] = ver
	m["revision"] = ver
	re := regexp.MustCompile(`^BUILD_METADATA_(.+)$`)
	for _, e := range os.Environ() {
		p := strings.SplitN(e, "=", 2)
		r := re.FindStringSubmatch(p[0])
		if r == nil {
			continue
		}
		k, v := strings.ToLower(r[1]), p[1]
		m[k] = v
	}
	f, err := os.Create(filepath.Join(path, "metadata.json"))
	if err != nil {
		return err
	}
	defer f.Close()
	e := json.NewEncoder(f)
	return e.Encode(m)
}
