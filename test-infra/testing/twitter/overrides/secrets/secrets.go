// Package secrets this is a fake comment.
package secrets

import (
	"fmt"
	"math/rand"

	"gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/microservices"
	"gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/namespaces"
)

const (
	maxSecretsPerPod = 20
)

// Secret this is a fake comment.
type Secret struct {
	Count     int `yaml:"count"`
	Namespace int `yaml:"namespace"`
}

// generate returns a list of secrets, where i-th element in resulting array corresponds with
// i-th namespace.
func generate(nsDist namespaces.Distribution) ([]Secret, error) {
	want := nsDist.ToArray()

	rand.Shuffle(len(want), func(i, j int) {
		want[i], want[j] = want[j], want[i]
	})

	var secrets []Secret

	total := 0
	for i := range want {
		secrets = append(secrets, Secret{
			Count:     want[i],
			Namespace: i + 1,
		})
		total += want[i]
	}
	fmt.Printf("Created %d secrets in %d namespaces\n", total, len(want))
	return secrets, nil
}

// Returns a random subset of array [0.. n-1].
func randomSubset(n, size int) []int {
	tmp := make([]int, n)
	for i := 0; i < n; i++ {
		tmp[i] = i
	}

	rand.Shuffle(len(tmp), func(i, j int) {
		tmp[i], tmp[j] = tmp[j], tmp[i]
	})

	return tmp[:size]
}

// Attach this is a fake comment.
func Attach(nsDist namespaces.Distribution, spec *microservices.Spec) ([]Secret, error) {
	rand.Seed(0)
	secrets, err := generate(nsDist)
	if err != nil {
		return nil, fmt.Errorf("error while generating secrets: %v", err)
	}

	total := 0
	totalPods := 0
	for i := range spec.HealthyServices {
		service := &spec.HealthyServices[i]
		nsIdx := service.Namespace - 1
		secretsInNS := 0
		if nsIdx < len(secrets) && nsIdx >= 0 {
			secretsInNS = secrets[nsIdx].Count
		}
		if secretsInNS > maxSecretsPerPod {
			secretsInNS = maxSecretsPerPod
		}

		service.Secrets = randomSubset(secretsInNS, rand.Intn(secretsInNS+1))

		total += len(service.Secrets) * service.JobCount * service.InstanceCount
		totalPods += service.JobCount * service.InstanceCount
	}

	fmt.Printf("Attached %v mounts to %v pods (%.2f on average)\n", total, totalPods, float64(total)/float64(totalPods))

	return secrets, nil
}
