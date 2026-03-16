package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestMain(m *testing.M) {
	initFlags()
	code := m.Run()
	os.Exit(code)
}

func TestFlagParsing(t *testing.T) {
	oldArgs := os.Args
	oldEnv := os.Getenv(gcloudContainerOverrideEnvVar)
	defer func() {
		os.Args = oldArgs
		os.Setenv(gcloudContainerOverrideEnvVar, oldEnv)
	}()

	tests := []struct {
		name            string
		envVars         map[string]string
		args            []string
		expectedOptions *proxyOptions
	}{
		{
			name: "Default options",
			args: []string{"cmd"},
			expectedOptions: &proxyOptions{
				targetHost:       "https://container.googleapis.com/",
				forceAlphaApi:    false,
				sleepAfterCreate: time.Duration(0),
			},
		},
		{
			name: "Flags set correctly",
			args: []string{"cmd", "--force-alpha-api", `--patch={"something":"yes"}`, "--target-host=https://targethost.com/"},
			expectedOptions: &proxyOptions{
				targetHost:       "https://targethost.com/",
				forceAlphaApi:    true,
				jsonPatches:      []string{`{"something":"yes"}`},
				sleepAfterCreate: time.Duration(0),
			},
		},
		{
			name:    "Environment variables set correctly (for gcloud)",
			envVars: map[string]string{gcloudContainerOverrideEnvVar: "https://targethost.com/", gproxyForceAlphaApiEnvVar: "True", sleepAfterCreateEnvVar: "10s"},
			args:    []string{"cmd"},
			expectedOptions: &proxyOptions{
				targetHost:       "https://targethost.com/",
				forceAlphaApi:    true,
				sleepAfterCreate: 10 * time.Second,
			},
		},
		{
			name:    "Environment variables set correctly (for terraform)",
			envVars: map[string]string{terraformContainerOverrideEnvVar: "https://targethost.com/", gproxyForceAlphaApiEnvVar: "True", sleepAfterCreateEnvVar: "10s"},
			args:    []string{"cmd"},
			expectedOptions: &proxyOptions{
				targetHost:       "https://targethost.com/",
				forceAlphaApi:    true,
				sleepAfterCreate: 10 * time.Second,
			},
		},
		{
			name:    "Flags and environment variables work together correctly",
			envVars: map[string]string{gcloudContainerOverrideEnvVar: "https://targethost.com/", gproxyForceAlphaApiEnvVar: "True", sleepAfterCreateEnvVar: "10s"},
			args:    []string{"cmd", "--force-alpha-api=false", `--patch={"something":"yes"}`, "--target-host=https://targethost.com/"},
			expectedOptions: &proxyOptions{
				targetHost:       "https://targethost.com/",
				forceAlphaApi:    false,
				jsonPatches:      []string{`{"something":"yes"}`},
				sleepAfterCreate: 10 * time.Second,
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			for k, v := range test.envVars {
				os.Setenv(k, v)
			}
			os.Args = test.args
			parseOptions()
			defer clearOptions(options)
			require.Equal(t, test.expectedOptions, options)
		})
	}
}

func TestProxy(t *testing.T) {
	oldArgs := os.Args
	oldEnv := os.Getenv(gcloudContainerOverrideEnvVar)
	defer func() {
		os.Args = oldArgs
		os.Setenv(gcloudContainerOverrideEnvVar, oldEnv)
	}()

	table := []struct {
		name         string
		urlPattern   string
		args         []string
		method       string
		requestBody  string
		expectedBody string
		expectedPath string
	}{
		{
			name:         "patch is applied",
			urlPattern:   "http://localhost:%d/clusters",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`},
			method:       "POST",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"test": true, "something": "yes"}}`,
			expectedPath: "/clusters",
		},
		{
			name:         "Multiple patches",
			urlPattern:   "http://localhost:%d/clusters",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`, "--patch", `{"cluster": {"test2": "ok"}}`},
			method:       "POST",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"test": true, "test2": "ok", "something": "yes"}}`,
			expectedPath: "/clusters",
		},
		{
			name:         "patch not applied due to incorrect url",
			urlPattern:   "http://localhost:%d/operation",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`},
			method:       "POST",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"something": "yes"}}`,
			expectedPath: "/operation",
		},
		{
			name:         "Patch not applied due to incorrect method",
			urlPattern:   "http://localhost:%d/clusters",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`, "--patch", `{"cluster": {"test2": "ok"}}`},
			method:       "PUT",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"something": "yes"}}`,
			expectedPath: "/clusters",
		},
		{
			name:         "Alpha API forced",
			urlPattern:   "http://localhost:%d/v1/clusters",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`, "--patch", `{"cluster": {"test2": "ok"}}`, "--force-alpha-api"},
			method:       "POST",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"test": true, "test2": "ok", "something": "yes"}}`,
			expectedPath: "/v1alpha1/clusters",
		},
		{
			name:         "Alpha API correctly forced, only the first v1 replaced",
			urlPattern:   "http://localhost:%d/v1/v1/v1beta1/v1alpha1/clusters",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`, "--patch", `{"cluster": {"test2": "ok"}}`, "--force-alpha-api"},
			method:       "POST",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"test": true, "test2": "ok", "something": "yes"}}`,
			expectedPath: "/v1alpha1/v1/v1beta1/v1alpha1/clusters",
		},
		{
			name:         "Alpha API correctly forced, only the first v1beta1 replaced",
			urlPattern:   "http://localhost:%d/v1beta1/v1/v1beta1/v1alpha1/clusters",
			args:         []string{"cmd", "--patch", `{"cluster": {"test": true}}`, "--patch", `{"cluster": {"test2": "ok"}}`, "--force-alpha-api"},
			method:       "POST",
			requestBody:  `{"cluster": {"something": "yes"}}`,
			expectedBody: `{"cluster": {"test": true, "test2": "ok", "something": "yes"}}`,
			expectedPath: "/v1alpha1/v1/v1beta1/v1alpha1/clusters",
		},
	}
	for _, item := range table {
		t.Run(item.name, func(t *testing.T) {
			svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				defer r.Body.Close()
				content, err := io.ReadAll(r.Body)
				if err != nil {
					t.Fatalf("Error when reading request body: %v", err)
				}
				require.Equal(t, item.expectedPath, r.URL.Path)
				fmt.Fprint(w, string(content))
			}))
			defer svr.Close()

			os.Setenv(gcloudContainerOverrideEnvVar, svr.URL)
			os.Args = item.args
			parseOptions()
			defer clearOptions(options)
			port, exit, server := runProxy()

			client := &http.Client{}
			req, err := http.NewRequest(item.method, fmt.Sprintf(item.urlPattern, port), strings.NewReader(item.requestBody))
			if err != nil {
				t.Fatalf("Error when creating request: %v", err)
			}
			resp, err := client.Do(req)
			if err != nil {
				t.Fatalf("Error when doing request: %v", err)
			}

			if err := server.Shutdown(context.TODO()); err != nil {
				t.Fatalf("Error when shutting down server: %v", err)
			}
			exit.Wait()

			defer resp.Body.Close()
			data, err := io.ReadAll(resp.Body)
			if err != nil {
				t.Fatalf("Error when reading response: %v", err)
			}
			actual := string(data)
			require.JSONEq(t, item.expectedBody, actual)
		})
	}
}

func TestDelay(t *testing.T) {
	os.Args = []string{"cmd", "ls"}
	sleepTime := "10s"
	os.Setenv(sleepAfterCreateEnvVar, sleepTime)
	parseOptions()
	start := time.Now()
	runProxiedCommand(0)
	dur := time.Since(start)
	expected, _ := time.ParseDuration(sleepTime)
	if dur < expected {
		t.Fatalf("expected to take at least: %s, runGcloud took: %s", sleepTime, dur)
	}
}

func clearOptions(o *proxyOptions) {
	o.forceAlphaApi = false
	o.jsonPatches = nil
	o.sleepAfterCreate = time.Duration(0)
	o.targetHost = ""
}
