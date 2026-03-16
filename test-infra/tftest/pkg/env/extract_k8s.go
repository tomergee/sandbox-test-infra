package env

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"

	"k8s.io/test-infra/kubetest/process"
)

type extractMode int

const (
	_ extractMode = iota
	gke
	gcs
	versionString
)

type ExtractStrategy struct {
	enabled bool
	mode    extractMode
	options []string
	value   string
}

// Make sure that the *ExtractStrategy implements the flag.Value interface. When
// the extract flag is parsed by flag.Var (https://pkg.go.dev/flag#Var), below
// *ExtractStrategy::Set() function is called. Which actually parses the flag's
// value and fills in the ExtractStrategy struct.
var _ flag.Value = &ExtractStrategy{}

func (e *ExtractStrategy) String() string {
	return e.value
}

func (e *ExtractStrategy) Enabled() bool {
	return e.enabled
}

func (e *ExtractStrategy) Set(value string) error {
	value = os.ExpandEnv(value)
	strategies := map[string]extractMode{
		`^gke-?(default|channel-(rapid|regular|stable)(?:-((?:[0-9]-)?latest))?|latest(-\d+.\d+(.\d+(-gke)?)?)?)?$`: gke,
		`^(gs://.*)$`:                 gcs,
		`^v(\d+\.\d+\.\d+[\w.\-+]*)$`: versionString,
	}
	for regex, mode := range strategies {
		re := regexp.MustCompile(regex)
		match := re.FindStringSubmatch(value)
		if match == nil || len(match) < 1 {
			continue
		}
		e.enabled = true
		e.mode = mode
		e.options = match
		e.value = value
		return nil
	}
	return fmt.Errorf("cannot parse gke version from '--extract' flag: %v", value)
}

func getVersionFromGKEStrategy(project, location string, options []string, control *process.Control) (string, error) {
	if strings.HasPrefix(options[1], "latest") {
		releasePrefix := ""
		if strings.HasPrefix(options[1], "latest-") {
			releasePrefix = strings.TrimPrefix(options[1], "latest-")
		}
		version, err := getLatestGKEVersion(project, location, releasePrefix, control)
		if err != nil {
			return "", fmt.Errorf("failed to get latest gke version: %v", err)
		}
		return version, nil
	}
	if strings.HasPrefix(options[1], "channel") {
		version, err := getChannelGKEVersion(project, location, options[2], options[3], control)
		if err != nil {
			return "", fmt.Errorf("failed to get gke version from channel %q: %s", options[2], err)
		}
		return version, nil
	}

	defaultVersion, err := control.Output(exec.Command("gcloud", "container", "get-server-config", fmt.Sprintf("--project=%v", project), fmt.Sprintf("--location=%v", location), "--format=value(defaultClusterVersion)"))
	if err != nil {
		return "", err
	}
	re := regexp.MustCompile(`(\d+\.\d+)(\..+)?$`)
	match := re.FindStringSubmatch(strings.TrimSpace(string(defaultVersion)))
	if match == nil {
		return "", fmt.Errorf("failed to parse version from %s", defaultVersion)
	}
	return match[1], nil
}

func getVersionFromGCSStrategy(options []string, control *process.Control) (string, error) {
	withoutGS := options[1][5:]
	version := path.Base(withoutGS)
	if strings.HasSuffix(options[1], ".txt") {
		url := fmt.Sprintf("gs://%v/%v", path.Dir(withoutGS), path.Base(withoutGS))
		release, err := control.Output(exec.Command("gsutil", "cat", url))
		if err != nil {
			return "", err
		}
		version = strings.TrimSpace(string(release))
	}
	version = strings.TrimPrefix(version, "v")
	return version, nil
}

func getVersionFromVersionString(options []string) (string, error) {
	if len(options) < 2 {
		return "", fmt.Errorf("cannot extract GKE version from %q", options[1])
	}
	return options[1], nil
}

func (e *ExtractStrategy) GetVersion(project, location string, control *process.Control) (string, error) {
	version := ""
	var err error
	switch e.mode {
	case gke:
		version, err = getVersionFromGKEStrategy(project, location, e.options, control)
	case gcs:
		version, err = getVersionFromGCSStrategy(e.options, control)
	case versionString:
		version, err = getVersionFromVersionString(e.options)
	default:
		err = fmt.Errorf("unrecognized extract mode %v", e.mode)
	}
	return version, err
}

func getLatestGKEVersion(project, location, releasePrefix string, control *process.Control) (string, error) {
	cmd := []string{
		"container",
		"get-server-config",
		fmt.Sprintf("--project=%v", project),
		fmt.Sprintf("--location=%v", location),
		"--format=value(validMasterVersions)",
	}

	res, err := control.Output(exec.Command("gcloud", cmd...))
	if err != nil {
		return "", err
	}
	versions := strings.Split(strings.TrimSpace(string(res)), ";")
	for _, version := range versions {
		if strings.HasPrefix(version, releasePrefix) {
			if version != "" {
				return version, nil
			}
		}
	}
	return "", fmt.Errorf("cannot find valid gke release %q version from: %s", releasePrefix, string(res))
}

func getChannelGKEVersion(project, location, gkeChannel, extractionMethod string, control *process.Control) (string, error) {
	cmd := []string{
		"container",
		"get-server-config",
		fmt.Sprintf("--project=%v", project),
		fmt.Sprintf("--location=%v", location),
		"--format=json(channels)",
	}

	type channel struct {
		Channel        string   `json:"channel"`
		DefaultVersion string   `json:"defaultVersion"`
		ValidVersions  []string `json:"validVersions"`
	}

	type channels struct {
		Channels []channel `json:"channels"`
	}

	res, err := control.Output(exec.Command("gcloud", cmd...))
	if err != nil {
		return "", err
	}

	var c channels
	if err := json.Unmarshal(res, &c); err != nil {
		return "", err
	}

	for _, channel := range c.Channels {
		if strings.EqualFold(channel.Channel, gkeChannel) {
			if strings.Contains(strings.ToLower(extractionMethod), "latest") {
				backstep := 0
				if unicode.IsDigit(rune(extractionMethod[0])) {
					backstep = int(extractionMethod[0]) - '0'
				}
				latestVersion, err := getGKELatestForMinor(channel.ValidVersions, backstep)
				if err != nil {
					return "", err
				}
				return latestVersion, nil
			} else {
				return channel.DefaultVersion, nil
			}
		}
	}

	return "", fmt.Errorf("cannot find a valid version for channel %q", gkeChannel)
}

type gkeVersion struct {
	major    int
	minor    int
	patch    int
	gkePatch int
}

func parseGkeVersion(s string) (*gkeVersion, error) {
	regex := "([0-9]+).([0-9]+).([0-9]+)-gke.([0-9]+)"
	re := regexp.MustCompile(regex)
	match := re.FindStringSubmatch(s)
	if len(match) < 4 {
		return nil, fmt.Errorf("could not parse gke version with regex: %s", regex)
	}
	major, err := strconv.Atoi(match[1])
	if err != nil {
		return nil, err
	}
	minor, err := strconv.Atoi(match[2])
	if err != nil {
		return nil, err
	}
	patch, err := strconv.Atoi(match[3])
	if err != nil {
		return nil, err
	}
	gkePatch, err := strconv.Atoi(match[4])
	if err != nil {
		return nil, err
	}

	return &gkeVersion{major, minor, patch, gkePatch}, nil
}

func (g gkeVersion) greater(o gkeVersion) bool {
	if g.major != o.major {
		return g.major > o.major
	}
	if g.minor != o.minor {
		return g.minor > o.minor
	}
	if g.patch != o.patch {
		return g.patch > o.patch
	}
	return g.gkePatch > o.gkePatch
}

func (g gkeVersion) String() string {
	return fmt.Sprintf("%d.%d.%d-gke.%d", g.major, g.minor, g.patch, g.gkePatch)
}

func convertToSortedGKEVersions(raw []string) ([]gkeVersion, error) {
	v := make([]gkeVersion, 0, len(raw))
	for _, s := range raw {
		version, err := parseGkeVersion(s)
		if err != nil {
			return nil, err
		}
		v = append(v, *version)
	}
	sort.Slice(v, func(i, j int) bool { return v[i].greater(v[j]) })
	return v, nil
}

func getGKELatestForMinor(raw []string, backstep int) (string, error) {
	versions, err := convertToSortedGKEVersions(raw)
	if err != nil {
		return "", err
	}
	if len(versions) == 0 {
		return "", fmt.Errorf("channel does not have valid versions")
	}
	targetMinor := versions[0].minor - backstep
	for _, v := range versions {
		if v.minor == targetMinor {
			return v.String(), nil
		}
	}
	return "", fmt.Errorf("minor %d is not available in selected channel", targetMinor)
}
