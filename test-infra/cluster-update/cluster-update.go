package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"golang.org/x/oauth2"

	jsonpatch "github.com/evanphx/json-patch"
	flag "github.com/spf13/pflag"
)

var (
	cluster     = flag.String("cluster", "", "Name of the cluster")
	project     = flag.String("project", "", "Project name")
	location    = flag.String("location", "", "Zone or region where the cluster resides")
	jsonPatches = flag.StringArray("patch", nil, "Patches to apply")
)

const (
	EXPECTED_OPERATION = "UPDATE_CLUSTER"
	EXPECTED_STATUS    = "RUNNING"
	EXPECTED_HTTP_CODE = 200
)

type resp struct {
	Name          string `json:"name"`
	Status        string `json:"status"`
	Zone          string `json:"zone"`
	SelfLink      string `json:"selfLink"`
	TargetLink    string `json:"targetLink"`
	OperationType string `json:"operationType"`
}

func prepareRequest(authToken string) *http.Request {

	targetHost := os.Getenv("CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER")
	if len(targetHost) == 0 {
		targetHost = "https://container.googleapis.com/"
	}
	endpoint := targetHost + strings.Join([]string{"v1alpha1", "projects", *project, "locations", *location, "clusters", *cluster}, "/")
	log.Printf("Target endpoint: %s\n", endpoint)

	content := []byte(`{}`)
	var err error
	for _, jsonPatch := range *jsonPatches {
		content, err = jsonpatch.MergePatch(content, []byte(jsonPatch))
		if err != nil {
			log.Fatal(err)
		}
	}

	log.Printf("Content: %v\n", string(content))

	reqBody := ioutil.NopCloser(bytes.NewBuffer(content))
	log.Printf("reqBody: %v\n", reqBody)
	req, err := http.NewRequest("PUT", endpoint, reqBody)
	if err != nil {
		log.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", authToken))
	req.Header.Set("Content-Length", strconv.Itoa(len(content)))

	return req
}

func updateCluster(req *http.Request) {
	log.Printf("req: %v", req)
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Fatal(err)
	}
	resBody, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil {
		log.Fatal(err)
	}
	log.Printf(string(resBody))
	r := resp{}
	if err = json.Unmarshal(resBody, &r); err != nil {
		log.Fatal(err)
	}
	log.Printf("Received response for cluster update:")
	log.Printf("- HTTP status code: %d", response.StatusCode)
	log.Printf("- Status: %s", response.Status)
	log.Printf("- Headers :")
	for k, v := range response.Header {
		log.Printf("  - key: %s, value: %v", k, v)
	}
	log.Printf("- ContentLength: %d", response.ContentLength)
	log.Printf("- Body: %v", response.Body)
	log.Printf("- TransferEncoding: %v", response.TransferEncoding)
	log.Printf("- Trailers :")
	for k, v := range response.Trailer {
		log.Printf("  - key: %s, value: %v", k, v)
	}
	log.Printf("- Request: %v", *response.Request)

	log.Printf("- Operation name: %s", r.Name)
	log.Printf("- Operation status: %s", r.Status)
	log.Printf("- Operation zone: %s", r.Zone)
	log.Printf("- Operation link: %s", r.SelfLink)
	log.Printf("- Cluster link: %s", r.TargetLink)

	if r.OperationType != EXPECTED_OPERATION {
		log.Fatal("Got unexpected operation type: %s, expected: %s", r.OperationType, EXPECTED_OPERATION)
	}
	if r.Status != EXPECTED_STATUS {
		log.Fatal("Got unexpected operation status: %s, expected: %s", r.Status, EXPECTED_STATUS)
	}
	if response.StatusCode != EXPECTED_HTTP_CODE {
		log.Fatal("Got unexpected HTTP code: %s, expected: %s", response.StatusCode, EXPECTED_HTTP_CODE)
	}
}

// configHelperResp corresponds to the JSON output of the `gcloud config-helper` command.
type configHelperResp struct {
	Configuration struct {
		Properties struct {
			Core struct {
				Account string `json:"account"`
			} `json:"core"`
		} `json:"properties"`
	} `json:"configuration"`
	Credential struct {
		AccessToken string `json:"access_token"`
		TokenExpiry string `json:"token_expiry"`
	} `json:"credential"`
}

func gcloudToken() (*oauth2.Token, error) {
	cmd := exec.Command("gcloud", "config", "config-helper", "--format=json")
	cmd.Env = os.Environ()
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("running the config-helper command: %w", err)
	}
	var r configHelperResp
	if err := json.Unmarshal(out, &r); err != nil {
		return nil, fmt.Errorf("parsing the config-helper output: %w", err)
	}
	log.Printf("account: %v\n", r.Configuration.Properties.Core.Account)
	log.Printf("token: %v\n", r.Credential.AccessToken)
	return &oauth2.Token{
		AccessToken: r.Credential.AccessToken,
		// Force refresh token every 10 seconds.
		//
		// This reduces the latency in picking up changes a user makes to their credentials
		// after the mixer startsup.
		Expiry: time.Now().Add(10 * time.Second),
	}, nil
}

type tokenSourceFunc func() (*oauth2.Token, error)

func (tsf tokenSourceFunc) Token() (*oauth2.Token, error) {
	return tsf()
}

func main() {
	flag.Parse()
	log.Printf("Cluster: %v\n", *cluster)
	log.Printf("Project: %v\n", *project)
	log.Printf("Location: %v\n", *location)
	log.Printf("Patches to apply: %v\n", *jsonPatches)
	log.Printf("Args: %v\n", flag.Args())

	tokenSource := oauth2.ReuseTokenSource(nil, tokenSourceFunc(gcloudToken))
	token, err := tokenSource.Token()
	if err != nil {
		log.Fatal("failure generating the authorization header: %v", err)
		return
	}
	req := prepareRequest(token.AccessToken)
	updateCluster(req)
}
