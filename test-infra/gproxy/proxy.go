package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path"
	"regexp"
	"strconv"
	"sync"
	"time"

	jsonpatch "github.com/evanphx/json-patch"
	flag "github.com/spf13/pflag"
)

const (
	gcloudContainerOverrideEnvVar    = "CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER"
	terraformContainerOverrideEnvVar = "GOOGLE_CONTAINER_CUSTOM_ENDPOINT"
	gproxyForceAlphaApiEnvVar        = "GPROXY_FORCE_ALPHA_API"
	gproxyLogAllRequestsEnvVar       = "GPROXY_LOG_ALL_REQUESTS"
	sleepAfterCreateEnvVar           = "SLEEP_AFTER_CREATE"
	defaultLogFileName               = "gproxy-request-log.json"
)

type proxyOptions struct {
	targetHost       string
	forceAlphaApi    bool
	jsonPatches      []string
	sleepAfterCreate time.Duration
	logAllRequests   bool
	requestLogFile   string
}

var options = &proxyOptions{}
var requestLogger *slog.Logger

// *Gproxy implements the http.RoundTripper interface
var _ http.RoundTripper = &Gproxy{}

type Gproxy struct {
	Proxy *httputil.ReverseProxy
}

func (*Gproxy) RoundTrip(req *http.Request) (*http.Response, error) {
	requestTime := time.Now()
	resp, err := http.DefaultTransport.RoundTrip(req)
	if err != nil {
		return resp, err
	}
	requestLatency := time.Since(requestTime)
	if options.logAllRequests {
		reqBody := ""
		respBody := ""
		if req.Body != nil {
			defer req.Body.Close()
			content, err := ioutil.ReadAll(req.Body)
			if err != nil {
				log.Fatal(err)
			}
			reqBody = string(content)
			req.Body = ioutil.NopCloser(bytes.NewBuffer(content))
		}
		if resp.Body != nil {
			defer resp.Body.Close()
			rawContent, err := ioutil.ReadAll(resp.Body)
			if err != nil {
				log.Fatal(err)
			}
			gzReader, err := gzip.NewReader(bytes.NewReader(rawContent))
			if err != nil {
				return nil, err
			}
			content, err := ioutil.ReadAll(gzReader)
			if err != nil {
				log.Fatal(err)
			}
			respBody = string(content)
			resp.Body = ioutil.NopCloser(bytes.NewBuffer(rawContent))
		}
		requestLogger.Debug("call proxied", slog.Group("request", "method", req.Method, "url", req.URL.Path, "body", reqBody), slog.Group("response", "status", resp.Status, "body", respBody), "latency", requestLatency.String())
	}
	return resp, err
}

func parseEnvVars() {
	if val, found := os.LookupEnv(gcloudContainerOverrideEnvVar); found {
		options.targetHost = val
	} else if val, found := os.LookupEnv(terraformContainerOverrideEnvVar); found {
		options.targetHost = val
	} else {
		options.targetHost = "https://container.googleapis.com/"
	}

	if val, found := os.LookupEnv(gproxyForceAlphaApiEnvVar); found {
		if b, err := strconv.ParseBool(val); err == nil {
			options.forceAlphaApi = b
		}
	}

	if val, found := os.LookupEnv(sleepAfterCreateEnvVar); found {
		delay, err := time.ParseDuration(val)
		if err != nil {
			log.Printf("could not parse %q env variable: %v", sleepAfterCreateEnvVar, err)
		} else {
			options.sleepAfterCreate = delay
		}
	}

	if val, found := os.LookupEnv("GPROXY_LOG_ALL_REQUESTS"); found {
		if b, err := strconv.ParseBool(val); err == nil {
			options.logAllRequests = b
		}
	}
}

func initRequestLogFile() *os.File {
	options.requestLogFile = os.ExpandEnv(options.requestLogFile)

	logDir := path.Dir(options.requestLogFile)
	if _, err := os.Stat(logDir); errors.Is(err, os.ErrNotExist) {
		log.Fatalf("directory for log file doesn't exist: %v", err)
	}

	if fileInfo, err := os.Stat(options.requestLogFile); err == nil {
		if fileInfo.IsDir() {
			options.requestLogFile = path.Join(options.requestLogFile, defaultLogFileName)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		log.Fatalf("error opening log file %q: %v", options.requestLogFile, err)
	}

	logFile, err := os.OpenFile(options.requestLogFile, os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
	if err != nil {
		log.Fatalf("error opening log file %q: %v", options.requestLogFile, err)
	}
	requestLogger = slog.New(slog.NewJSONHandler(logFile, &slog.HandlerOptions{Level: slog.LevelDebug}))
	return logFile
}

func initFlags() {
	flag.StringArrayVar(&options.jsonPatches, "patch", nil, "Patches to apply")
	flag.StringVar(&options.targetHost, "target-host", "", "Target host")
	flag.BoolVar(&options.forceAlphaApi, "force-alpha-api", false, "Force using the alpha version of the GKE API in the proxied requests")
	flag.BoolVar(&options.logAllRequests, "log-all-requests", false, "Log every proxied request and response to requests-log-file")
	flag.StringVar(&options.requestLogFile, "requests-log-file", defaultLogFileName, "File to log all requests and responses.")
}

func parseOptions() {
	// Parse environment variables before flags so that flags take precedence.
	parseEnvVars()
	flag.Parse()

	log.Printf("Target Host: %v\n", options.targetHost)
	log.Printf("Force AlphaAPI: %v\n", options.forceAlphaApi)
	log.Printf("Log All Requests: %v\n", options.logAllRequests)
	log.Printf("Requests Log File: %v\n", options.requestLogFile)
	log.Printf("Patches: %v\n", options.jsonPatches)
	log.Printf("Args: %v\n", flag.Args())
}

func NewProxy() (*Gproxy, error) {
	log.Printf("Target env: %s\n", options.targetHost)
	target, err := url.Parse(options.targetHost)
	if err != nil {
		return nil, err
	}

	gp := Gproxy{
		Proxy: httputil.NewSingleHostReverseProxy(target),
	}
	gp.Proxy.Transport = &gp

	default_director := gp.Proxy.Director

	director := func(req *http.Request) {
		default_director(req)
		req.Host = target.Host

		log.Printf("Request:%s %s", req.Method, req.URL.Path)
		matches, err := regexp.MatchString("clusters$", req.URL.Path)
		if err != nil {
			log.Fatal(err)
		}
		if req.Method != "POST" || !matches {
			return
		}
		if options.forceAlphaApi {
			re := regexp.MustCompile(`^(\/v1(beta1)?\/)`)
			req.URL.Path = re.ReplaceAllString(req.URL.Path, "/v1alpha1/")
			log.Printf("Forcing Alpha API. New path: %s", req.URL.Path)
		}

		if req.Body != nil {
			defer req.Body.Close()
			content, err := ioutil.ReadAll(req.Body)
			if err != nil {
				log.Fatal(err)
			}
			if len(content) > 0 {
				for _, jsonPatch := range options.jsonPatches {
					content, err = jsonpatch.MergePatch(content, []byte(jsonPatch))
					if err != nil {
						log.Printf("Content prior to patch: %v\n", string(content))
						log.Fatalf("Failed to apply patch %q: %v", jsonPatch, err)
					}
				}

				log.Printf("Content: %v\n", string(content))
			}

			req.Header.Set("Content-Length", strconv.Itoa(len(content)))
			req.ContentLength = int64(len(content))
			req.Body = ioutil.NopCloser(bytes.NewBuffer(content))
		}

	}
	gp.Proxy.Director = director
	return &gp, nil
}

func startHttpServer(proxy *httputil.ReverseProxy, listener net.Listener, exit *sync.WaitGroup) *http.Server {
	srv := &http.Server{Addr: ":0", Handler: proxy}
	exit.Add(1)

	go func() {
		defer exit.Done()

		if err := srv.Serve(listener); err != http.ErrServerClosed {
			log.Fatalf("Serve(): %v", err)
		}
	}()
	return srv
}

func runProxy() (port int, exit *sync.WaitGroup, server *http.Server) {
	proxy, err := NewProxy()
	if err != nil {
		log.Fatal(err)
	}

	listener, err := net.Listen("tcp", ":0")
	if err != nil {
		log.Fatal(err)
	}

	port = listener.Addr().(*net.TCPAddr).Port
	exit = &sync.WaitGroup{}
	server = startHttpServer(proxy.Proxy, listener, exit)
	return
}

func runProxiedCommand(port int) {
	log.Printf("Running: %v", flag.Args())
	cmd := exec.Command(flag.Args()[0], flag.Args()[1:]...)
	cmd.Env = os.Environ()
	cmd.Env = append(cmd.Env, fmt.Sprintf(`%s=http://localhost:%d/`, gcloudContainerOverrideEnvVar, port))
	cmd.Env = append(cmd.Env, fmt.Sprintf(`%s=http://localhost:%d/`, terraformContainerOverrideEnvVar, port))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()

	if err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			os.Exit(exitError.ExitCode())
		} else {
			log.Fatalf("Running command failed: %v", err)
		}
	}

	if options.sleepAfterCreate != time.Duration(0) {
		log.Printf("Sleeping after creation for %s", options.sleepAfterCreate)
		time.Sleep(options.sleepAfterCreate)
	}
}

func main() {
	initFlags()
	parseOptions()
	if options.logAllRequests {
		logFile := initRequestLogFile()
		defer logFile.Close()
	}

	port, exit, server := runProxy()
	log.Printf("Server port: %v\n", port)
	runProxiedCommand(port)

	if err := server.Shutdown(context.TODO()); err != nil {
		log.Fatal(err)
	}
	exit.Wait()
}
