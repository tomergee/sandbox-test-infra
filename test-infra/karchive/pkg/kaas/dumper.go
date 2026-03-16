package kaas

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	artifactsEnvVarName      = "ARTIFACTS"
	podNamePlaceholder       = "[PUT POD NAME HERE]"
	podNamespacePlaceholder  = "[PUT POD NAMESPACE HERE]"
	nodeNamePlaceholder      = "[PUT NODE NAME HERE]"
	maxFailedPodsPerArtifact = 5
)

func CreateRunInfo(name, location, project, hash string) (*RunInfo, error) {
	// Configuration exposed within cluster is preferred.
	ci, err := getClusterInfo()
	if err != nil {
		if name == "" && location == "" && project == "" {
			return nil, err
		}
		log.Printf("failed to fetch cluster config: %v\n", err)
		// Let's do our best.
		log.Printf("falling back to {%s, %s, %s}\n", name, location, project)
		ci = &ClusterInfo{
			Name:      name,
			Location:  location,
			ProjectID: project,
			Hash:      hash,
		}
	}

	ji, err := getJobInfo()
	if err != nil {
		return nil, err
	}

	return &RunInfo{
		ClusterInfo: ci,
		JobInfo:     ji,
	}, nil
}

type link struct {
	Name string `json:"name"`
	Url  string `json:"url"`
}

type linkGroup struct {
	Title string `json:"title"`
	Links []link `json:"links"`
}

func (runInfo *RunInfo) DumpLinks() {
	pprofLinks := []link{}
	if pprofUrl, ok := runInfo.GetProfilesURL(); ok {
		pprofLinks = append(pprofLinks, link{
			Name: "Profiles",
			Url:  pprofUrl,
		})
	}

	artifactsToDump := map[string]linkGroup{
		"gke-admin-ui": {
			Title: "GKE Admin UI",
			Links: []link{
				{
					Name: "GKE Admin UI",
					Url:  runInfo.GetGKEAdminUIURL(),
				},
			},
		},
		"analog-logs": {
			Title: "Analog logs",
			Links: []link{
				{
					Name: "Cluster Server",
					Url:  runInfo.GetAnalogURL("apiserver", "cluster_apiserver"),
				},
				{
					Name: "Cluster Server (Pod)",
					Url:  runInfo.GetAnalogPodURL("cluster-server"),
				},
				{
					Name: "Hosted Master Server",
					Url:  runInfo.GetAnalogURL("hostedmaster", "hosted_master_server"),
				},
				{
					Name: "Hosted Master Server (Pod)",
					Url:  runInfo.GetAnalogPodURL("hosted-master-server"),
				},
				{
					Name: "Audit Server",
					Url:  runInfo.GetAnalogURL("hostedmaster", "audit_server"),
				},
				{
					Name: "Monitoring Server",
					Url:  runInfo.GetAnalogURL("main", "monitoring_server"),
				},
			},
		},
		"master-logs": {
			Title: "Master logs - read b/354886696(link below) on how to display master logs",
			Links: []link{
				{
					Name: "b/354886696",
					Url:  "https://b.corp.google.com/issues/354886696#comment1",
				},
				{
					Name: "All master logs",
					Url:  runInfo.GetSdMasterURL("", ""),
				},
				{
					Name: "Serial console logs",
					Url:  runInfo.GetSdMasterConsoleURL(""),
				},
				{
					Name: "OOM logs",
					Url:  runInfo.GetSdMasterURL("kubelet", "OOMKilled"),
				},
				{
					Name: "kubelet logs",
					Url:  runInfo.GetSdMasterURL("kubelet", ""),
				},
				{
					Name: "cluster-autoscaler logs",
					Url:  runInfo.GetSdMasterURL("cluster-autoscaler", ""),
				},
				{
					Name: "kube-apiserver logs",
					Url:  runInfo.GetSdMasterURL("kube-apiserver", ""),
				},
				{
					Name: "kube-controller-manager logs",
					Url:  runInfo.GetSdMasterURL("kube-controller-manager", ""),
				},
				{
					Name: "kube-scheduler logs",
					Url:  runInfo.GetSdMasterURL("kube-scheduler", ""),
				},
				{
					Name: "etcd logs",
					Url:  runInfo.GetSdMasterURL("etcd", ""),
				},
				{
					Name: "etcd-events logs",
					Url:  runInfo.GetSdMasterURL("etcd-events", ""),
				},
				{
					Name: "gke-kspan-proxy",
					Url:  runInfo.GetSdMasterURL("gke-kspan-proxy", ""),
				},
				{
					Name: "[deprecated, won't work with tenant projects] BigQuery logs",
					Url:  "http://pantheon/bigquery?project=" + runInfo.MasterProjectID,
				},
				{
					Name: "[deprecated, won't work with tenant projects] HMP project in Google Admin",
					Url:  "http://ga/search/" + runInfo.MasterProjectID,
				},
			},
		},
		"node-logs": {
			Title: "Node logs",
			Links: []link{
				{
					Name: "Container runtime logs",
					Url:  runInfo.GetNodeComponentURL("container-runtime", nodeNamePlaceholder),
				},
				{
					Name: "Kubelet logs",
					Url:  runInfo.GetNodeComponentURL("kubelet", nodeNamePlaceholder),
				},
				{
					Name: "Kube-proxy logs",
					Url:  runInfo.GetNodeComponentURL("kube-proxy", nodeNamePlaceholder),
				},
				{
					Name: "Node OOM logs",
					Url:  runInfo.GetSdOomURL(),
				},
				{
					Name: "Node container logs",
					Url:  runInfo.GetSdContainerURL(),
				},
			},
		},
		"audit-logs": {
			Title: "Audit logs",
			Links: []link{
				{
					Name: "Audit logs",
					Url:  runInfo.GetAuditLogURL(),
				},
				{
					Name: "All we know about a pod",
					Url:  runInfo.GetLifeOfAPodURL(podNamePlaceholder, podNamespacePlaceholder),
				},
			},
		},
		"pprofs": {
			Title: "Profiles (if available)",
			Links: pprofLinks,
		},
	}

	pantheonURLTitle := "Pantheon view"
	if runInfo.Environment == "test" || runInfo.Environment == "staging" || runInfo.Environment == "staging2" {
		pantheonURLTitle += fmt.Sprintf(" (requires access from https://grants.corp.google.com/#/grants?request=4h%%2Fcloud-kubernetes-%s-hmp-compute-viewers)", runInfo.Environment)
	}
	for _, mr := range runInfo.MasterResources {
		group := linkGroup{
			Title: fmt.Sprintf("Master %s links", mr.ID),
			Links: []link{
				{
					Name: pantheonURLTitle,
					Url:  "http://pantheon/project/" + runInfo.MasterProjectID + "/compute/instancesDetail/zones/" + mr.Zone + "/instances/" + mr.Name,
				},
			},
		}
		artifactsToDump[mr.ID] = group
	}

	failedPodsLinks, err := runInfo.getFailedPodsLinks()
	if err != nil {
		log.Printf("unable to create pod links: %v", err)
	}
	if len(failedPodsLinks) != 0 {
		group := linkGroup{
			Title: "Failed Pods",
			Links: failedPodsLinks,
		}
		artifactsToDump["failed-pods"] = group
	}

	for filename, linkGroup := range artifactsToDump {
		content, err := json.MarshalIndent(linkGroup, "", "    ")
		if err != nil {
			fmt.Printf("unable to marshal %v: %v\n", linkGroup, err)
			continue
		}
		if err := dumpLinkJsonArtifact(filename, string(content)); err != nil {
			fmt.Printf("unable to dump %v: %v\n", filename, err)
		}
	}
}

func (runInfo *RunInfo) DumpKarchiveData() error {
	runInfoJson, err := json.MarshalIndent(runInfo, "", "    ")
	if err != nil {
		return fmt.Errorf("problem with JSON conversion: %w", err)
	}
	return dumpJsonArtifact("karchive-data", string(runInfoJson))
}

func (runInfo *RunInfo) DumpInternalIps(filepath string) error {
	ips := []string{}

	for _, mr := range runInfo.MasterResources {
		// Try to use the IP address assigned to etcd replica and fall back
		// to the master's internal IP if it doesn't have etcd nor its etcd
		// replica doesn't have an IP alias assigned.
		if mr.EtcdIPAddress != "" {
			ips = append(ips, mr.EtcdIPAddress)
		} else if mr.InternalIPAddress != "" {
			ips = append(ips, mr.InternalIPAddress)
		}
	}
	contents := strings.Join(ips, ",")

	file, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer file.Close()
	file.WriteString(contents)
	return file.Sync()
}

func (runInfo *RunInfo) DumpPublicIps(filepath string) error {
	ips := []string{}

	for _, mr := range runInfo.MasterResources {
		if mr.IPAddress != "" {
			ips = append(ips, mr.IPAddress)
		}
	}
	contents := strings.Join(ips, ",")

	file, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer file.Close()
	file.WriteString(contents)
	return file.Sync()
}

// Dumps relevant contents to the file inside $ARTIFACTS subdirectory.
// kubetest automatically pushes the whole subdirectory to the job's GCS bucket.
func dumpArtifact(filename, contents string) error {
	artifactPath := filepath.Join(os.Getenv(artifactsEnvVarName), filename)
	file, err := os.Create(artifactPath)
	if err != nil {
		return err
	}
	defer file.Close()
	file.WriteString(contents)
	return file.Sync()
}

// Filename with the .link.json suffix makes the respective file contents visible
// in the "links" lens after the Prow job runs to completion.
func dumpLinkJsonArtifact(artifactName, contents string) error {
	filename := fmt.Sprintf("%s.link.json", artifactName)
	return dumpArtifact(filename, contents)
}

func dumpJsonArtifact(artifactName, contents string) error {
	filename := fmt.Sprintf("%s.json", artifactName)
	return dumpArtifact(filename, contents)
}

func GetKarchiveData() (*RunInfo, error) {
	data, err := fetchArtifact("karchive-data.json")
	if err != nil {
		return nil, err
	}
	runInfo := &RunInfo{&JobInfo{}, &ClusterInfo{}}
	if err = json.Unmarshal(data, runInfo); err != nil {
		return nil, err
	}
	runInfo.JobFinishTimestamp = time.Now().Add(5 * time.Minute).Round(time.Second)
	return runInfo, nil
}

// Get the contents of a particular artifact.
func fetchArtifact(filename string) ([]byte, error) {
	artifactPath := filepath.Join(os.Getenv(artifactsEnvVarName), filename)
	data, err := ioutil.ReadFile(artifactPath)
	if err != nil {
		return []byte{}, err
	}
	return data, nil
}

func getArtifactsWithRegex(regex string) ([]string, error) {
	files, err := os.ReadDir(os.Getenv(artifactsEnvVarName))
	if err != nil {
		return nil, fmt.Errorf("failed to read artifacts dir: %v", files)
	}
	res := []string{}
	for _, f := range files {
		ok, err := regexp.Match(regex, []byte(f.Name()))
		if err != nil {
			log.Printf("failed to match artifacts name with regex: %v", err)
		}
		if ok {
			res = append(res, f.Name())
		}
	}
	return res, nil
}

type failedPod struct {
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
}

func (runInfo *RunInfo) getFailedPodsLinks() ([]link, error) {
	artifacts, err := getArtifactsWithRegex(".*_failedpods_*")
	if err != nil {
		return nil, fmt.Errorf("could not get artifacts for failed pods: %v", err)
	}
	links := []link{}
	for _, artifact := range artifacts {
		data, err := fetchArtifact(artifact)
		if err != nil {
			log.Printf("could not fetch artifact: %v", err)
			continue
		}
		fp := []failedPod{}
		if err = json.Unmarshal(data, &fp); err != nil {
			log.Printf("could not unmarshal artifact: %v", err)
			continue
		}
		for i := 0; i < len(fp) && i < maxFailedPodsPerArtifact; i++ {
			l := link{
				Name: fp[i].Name,
				Url:  runInfo.GetLifeOfAPodURL(fp[i].Name, fp[i].Namespace),
			}
			links = append(links, l)
		}
	}
	return links, nil
}

// GetAnalogURL creates link to analog for given process and a job
func (runInfo *RunInfo) GetAnalogURL(process, job string) string {
	var user string
	switch runInfo.Environment {
	case "prod":
		user = "cloud-kubernetes"
	case "staging", "staging2":
		user = "cloud-kubernetes-" + runInfo.Environment
	default:
		user = "cloud-kubernetes-test"
	}
	fullyQualifiedJob := fmt.Sprintf("%s.cloud_kubernetes.%s.%s", runInfo.Environment, runInfo.Location, job)

	return runInfo.createAnalogURL(process, fullyQualifiedJob, user, process == "hostedmaster")
}

func (runInfo *RunInfo) GetAnalogPodURL(podNode string) string {
	return runInfo.createAnalogURL("", runInfo.podJob(podNode), runInfo.podUser(podNode), podNode == "hosted-master-server")
}

func (runInfo *RunInfo) createAnalogURL(process, job, user string, searchByClusterName bool) string {
	textQuery := `resource.type="borg.producer"`
	if process != "" {
		textQuery += fmt.Sprintf(" resource.labels.process_name=\"%s\"", process)
	}
	if user != "" {
		textQuery += fmt.Sprintf(" resource.labels.borg_user=\"%s\"", user)
	}
	if job != "" {
		textQuery += fmt.Sprintf(" resource.labels.borg_job=\"%s\"", job)
	}
	if searchByClusterName || runInfo.ClusterInfo.Hash == "" {
		textQuery += fmt.Sprintf(" text_payload=~\"%s\"", runInfo.ClusterInfo.Name)
	} else {
		textQuery += fmt.Sprintf(" text_payload=~\"%s\"", runInfo.ClusterInfo.Hash)
	}

	params := url.Values{}
	params.Add("text_query", textQuery)

	timeFormat := "2006-01-02T15:04:05.00000Z0700"
	timeRange := fmt.Sprintf("%s/%s", runInfo.JobStartTimestamp.UTC().Format(timeFormat), runInfo.JobFinishTimestamp.UTC().Format(timeFormat))
	params.Add("time_range", timeRange)

	return "http://analog-ng/query?" + params.Encode()
}

func (runInfo *RunInfo) createSdURL(params url.Values, timestamp bool) string {
	params.Add("interval", "CUSTOM")
	params.Add("dateRangeStart", runInfo.JobStartTimestamp.Format(time.RFC3339))
	params.Add("dateRangeEnd", runInfo.JobFinishTimestamp.Format(time.RFC3339))
	timestampFilter := fmt.Sprintf(
		`timestamp>="%s" timestamp<="%s"`,
		runInfo.JobStartTimestamp.Format(time.RFC3339),
		runInfo.JobFinishTimestamp.Format(time.RFC3339),
	)
	params.Set("advancedFilter", params.Get("advancedFilter")+"\n"+timestampFilter)
	return "http://pantheon/logs/viewer?" + params.Encode()
}

// GetSdMasterURL constructs Stackdriver url for a master component
// TODO(b/348137784): add unit test coverage.
func (runInfo *RunInfo) GetSdMasterURL(component string, additionalFilter string) string {
	if runInfo.MasterProjectID == "" {
		return "no Pantheon link without master project ID"
	}
	params := url.Values{}
	params.Add("project", runInfo.getMasterLogsProject())
	var filter []string
	filter = append(filter, fmt.Sprintf(`resource.labels.project_id="%s"`, runInfo.MasterProjectID))
	filter = append(filter, `(resource.type="gce_instance" OR resource.type="container")`)
	var masters []string
	for _, master := range runInfo.MasterResources {
		masters = append(masters, master.ID+"-")
	}
	filter = append(filter, fmt.Sprintf(`labels."compute.googleapis.com/resource_name":("%s")`, strings.Join(masters, `" OR "`)))
	if component != "" {
		filter = append(filter, fmt.Sprintf(
			`logName="projects/%s/logs/%s"`,
			runInfo.MasterProjectID, component))
	}
	if additionalFilter != "" {
		filter = append(filter, additionalFilter)
	}
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	// Setting storage scope for all locations. This is what jump/gke-{env}-kcp-logs does.
	// Using only the shard for specific location is unlikely to make a performance difference outside of prod.
	params.Add("storageScope", fmt.Sprintf("storage,projects%%2Fgke-%[1]s-bq-logs%%2Flocations%%2Fglobal%%2Fbuckets%%2Fgke_%[1]s_kcp_logs_asia%%2Fviews%%2F_AllLogs,projects%%2Fgke-%[1]s-bq-logs%%2Flocations%%2Fglobal%%2Fbuckets%%2Fgke_%[1]s_kcp_logs_eu%%2Fviews%%2F_AllLogs,projects%%2Fgke-%[1]s-bq-logs%%2Flocations%%2Fglobal%%2Fbuckets%%2Fgke_%[1]s_kcp_logs_other%%2Fviews%%2F_AllLogs,projects%%2Fgke-%[1]s-bq-logs%%2Flocations%%2Fglobal%%2Fbuckets%%2Fgke_%[1]s_kcp_logs_us%%2Fviews%%2F_AllLogs", runInfo.Environment))
	return runInfo.createSdURL(params, true)
}

func (runInfo *RunInfo) getMasterLogsProject() string {
	if runInfo.Environment == "dev" {
		return "gke-dev-kcp-logs"
	}
	return fmt.Sprintf("gke-%s-bq-logs", runInfo.Environment)
}

// GetSdMasterConsoleURL constructs Stackdriver url for master serial console
func (runInfo *RunInfo) GetSdMasterConsoleURL(additionalFilter string) string {
	if runInfo.MasterProjectID == "" {
		return "no Pantheon link without HMP project ID"
	}
	params := url.Values{}
	params.Add("project", runInfo.MasterProjectID)
	var filter []string
	filter = append(filter, `resource.type="gce_instance"`)
	var instances []string
	for _, master := range runInfo.MasterResources {
		if master.InstanceID != "" {
			instances = append(instances, master.InstanceID)
		}
	}
	if len(instances) == 0 {
		return "no Pantheon link without master instance ID"
	}
	filter = append(filter, fmt.Sprintf(`resource.labels.instance_id:(%s)`, strings.Join(instances, ` OR `)))
	filter = append(filter, fmt.Sprintf(`logName="projects/%s/logs/serialconsole.googleapis.com%%2Fserial_port_1_output"`, runInfo.MasterProjectID))
	if additionalFilter != "" {
		filter = append(filter, additionalFilter)
	}
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	return runInfo.createSdURL(params, true)
}

// GetSdOomURL constructs Stackdriver url for OOMing processes on nodes
func (runInfo *RunInfo) GetSdOomURL() string {
	params := url.Values{}
	params.Add("project", runInfo.ProjectID)
	var filter []string
	filter = append(filter, `resource.type="gce_instance"`)
	filter = append(filter, fmt.Sprintf(`logName="projects/%s/logs/serialconsole.googleapis.com%%2Fserial_port_1_output"`, runInfo.ProjectID))
	filter = append(filter, `("Memory cgroup" OR "oom_reaper")`)
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	return runInfo.createSdURL(params, true)
}

// GetSdContainerURL constructs Stackdriver url for pods in a cluster
func (runInfo *RunInfo) GetSdContainerURL() string {
	params := url.Values{}
	params.Add("project", runInfo.ProjectID)
	var filter []string
	filter = append(filter, `resource.type="k8s_container"`)
	filter = append(filter, fmt.Sprintf(`resource.labels.cluster_name="%s"`, runInfo.Name))
	filter = append(filter, `resource.labels.namespace_name="kube-system"`)
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	return runInfo.createSdURL(params, true)
}

// GetSdContainerURL constructs Stackdriver url for pods in a cluster
func (runInfo *RunInfo) GetNodeComponentURL(componentName, nodeName string) string {
	params := url.Values{}
	params.Add("project", runInfo.ProjectID)
	var filter []string
	filter = append(filter, `resource.type="k8s_node"`)
	filter = append(filter, fmt.Sprintf(`logName="projects/%s/logs/%s"`, runInfo.ProjectID, componentName))
	filter = append(filter, fmt.Sprintf(`resource.labels.cluster_name="%s"`, runInfo.Name))
	filter = append(filter, fmt.Sprintf(`resource.labels.node_name="%s"`, nodeName))
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	return runInfo.createSdURL(params, true)
}

func (runInfo *RunInfo) GetAuditLogURL() string {
	params := url.Values{}
	params.Add("project", runInfo.ProjectID)
	var filter []string
	filter = append(filter, `resource.type="k8s_cluster"`)
	filter = append(filter, fmt.Sprintf(`resource.labels.cluster_name="%s"`, runInfo.Name))
	filter = append(filter, fmt.Sprintf(`logName="projects/%s/logs/cloudaudit.googleapis.com%%2Factivity"`, runInfo.ProjectID))
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	return runInfo.createSdURL(params, true)
}
func (runInfo *RunInfo) GetLifeOfAPodURL(name, namespace string) string {
	params := url.Values{}
	params.Add("project", runInfo.ProjectID)
	var filter []string
	filter = append(filter, `resource.type="k8s_cluster" OR resource.type="k8s_node" OR resource.type = "k8s_control_plane_component"`)
	filter = append(filter, fmt.Sprintf(`resource.labels.cluster_name="%s"`, runInfo.Name))
	filter = append(filter, name, namespace)
	params.Add("advancedFilter", strings.Join(filter, "\n"))
	return runInfo.createSdURL(params, true)
}

func (runInfo *RunInfo) GetGKEAdminUIURL() string {
	if runInfo.Hash == "" {
		return "no cluster hash provided"
	}
	if runInfo.IsSandbox {
		return "GKE Admin UI doesn't support sandbox"
	}
	return fmt.Sprintf("http://gke/%s?env=%s", runInfo.Hash, runInfo.Environment)
}

func (runInfo *RunInfo) GetProfilesURL() (string, bool) {
	const prefixLen = 20
	if len(runInfo.Hash) < prefixLen {
		log.Printf("Unexpectedly short cluster hash (%q): no profile URLs will be displayed.", runInfo.Hash)
		return "", false
	}
	urlPath := fmt.Sprintf("storage/browser/gke-scalability-pprofs/gke-%s", runInfo.Hash[:prefixLen])
	return fmt.Sprintf("http://pantheon/%s?project=gke-scalability-pprofs", urlPath), true
}

func (runInfo *RunInfo) DumpComponentsVersions() error {
	componentsJson, err := json.MarshalIndent(runInfo.ComponentsVersions, "", "    ")
	if err != nil {
		return fmt.Errorf("problem with JSON conversion: %w", err)
	}
	return dumpJsonArtifact("components-versions", string(componentsJson))
}

// adapted from https://source.corp.google.com/piper///depot/google3/cloud/kubernetes/engine/common/testing/debug_links.go
// to be able to add logs for jobs migrated to Pod
func (runInfo *RunInfo) podJob(podNode string) string {
	return fmt.Sprintf("%s-%s.%s", runInfo.podEnv(), runInfo.Location, podNode)
}

func (runInfo *RunInfo) podUser(podNode string) string {
	switch runInfo.Environment {
	case "test":
		return fmt.Sprintf("cloud-kubernetes-%s-test-jobs", podNode)
	case "staging2":
		return fmt.Sprintf("cloud-kubernetes-%s-staging2-jobs", podNode)
	case "staging":
		return fmt.Sprintf("cloud-kubernetes-%s-staging-jobs", podNode)
	case "prod":
		return fmt.Sprintf("cloud-kubernetes-%s", podNode)
	case "tpc":
		// TODO(b/303234257): update this func to have more generic to works with all pod env.
		return fmt.Sprintf("tpcl-gdutst-cloud-kubernetes-%s-test-jobs", podNode)
	default:
		// Sandbox
		return "cloud-kubernetes-test"
	}
}

func (runInfo *RunInfo) podEnv() string {
	switch runInfo.Environment {
	case "test":
		return "autopush-qual"
	case "staging":
		return "preprod-qual"
	case "staging2":
		return "staging-qual"
	case "prod":
		return "prod"
	default:
		return "UNEXPECTED_ENVIRONMENT"
	}
}
