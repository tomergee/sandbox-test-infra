package gproxysetup

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func SetupGproxy() {
	wrapperDir := "/wrapper"
	if err := os.MkdirAll(wrapperDir, 0755); err != nil {
		log.Fatalf("failed to create gproxy wrapper directory: %v", err)
	}

	gcloudWrapperPath := filepath.Join(wrapperDir, "gcloud")
	gcloudPath := "/google-cloud-sdk/bin/gcloud"
	gproxyPath := "/gproxy"

	scriptContent := fmt.Sprintf(`#!/bin/bash
set -e

gproxyPath="%s"
gcloudPath="%s"

readarray -t patches < <(printf '%%s\n' "${GPROXY_PATCHES}" | sed '/^$/d')

declare -a gproxy_args
for patch in "${patches[@]}"; do
  if [[ -n "${patch}" ]]; then
    gproxy_args+=("--patch")
    gproxy_args+=("${patch}")
  fi
done

exec "${gproxyPath}" "${gproxy_args[@]}" -- "${gcloudPath}" "$@"
`, gproxyPath, gcloudPath)

	if err := os.WriteFile(gcloudWrapperPath, []byte(scriptContent), 0755); err != nil {
		log.Fatalf("failed to write gcloud wrapper script: %v", err)
	}
}

func SetupGproxyCommand(cmd *exec.Cmd, patches []string) *exec.Cmd {
	originalPath := os.Getenv("PATH")
	newPath := fmt.Sprintf("/wrapper:%s", originalPath)

	if cmd.Env == nil {
		cmd.Env = os.Environ()
	}

	cmd.Env = append(cmd.Env, fmt.Sprintf("GPROXY_PATCHES=%s", os.ExpandEnv(strings.Join(patches, "\n"))))
	foundPath := false
	for i, env := range cmd.Env {
		if strings.HasPrefix(env, "PATH=") {
			cmd.Env[i] = fmt.Sprintf("PATH=%s", newPath)
			foundPath = true
			break
		}
	}
	if !foundPath {
		cmd.Env = append(cmd.Env, fmt.Sprintf("PATH=%s", newPath))
	}

	return cmd
}
