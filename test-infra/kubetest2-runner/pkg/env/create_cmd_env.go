package env

import "os"

func CreateCmdEnv(env []string) []string {
	execEnv := os.Environ()
	for _, v := range env {
		execEnv = append(execEnv, v)
	}
	return execEnv
}
