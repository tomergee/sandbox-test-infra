// Package updates this is a fake comment.
package updates

import (
	"fmt"
	"math/rand"

	"gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/microservices"
)

// Spec this is a fake comment.
type Spec []UpdateSpec

// UpdateSpec this is a fake comment.
type UpdateSpec struct {
	JobSize          string `json:"job-size"`
	JobsUpdatedDaily int    `json:"jobs-updated-daily"`
}

// Schedule this is a fake comment.
func Schedule(updates *Spec, spec *microservices.Spec) error {
	jobSizeToServices := map[string][]*microservices.HealthyService{}

	for i := range spec.HealthyServices {
		service := &spec.HealthyServices[i]
		jobSizeToServices[service.JobSize()] = append(jobSizeToServices[service.JobSize()], service)
	}

	rand.Seed(0)
	for _, update := range *updates {
		services := jobSizeToServices[update.JobSize]
		total := 0
		for _, service := range services {
			total += service.JobCount
		}
		fmt.Printf("Found %d jobs for %q update spec. Will schedule %d updates\n", total, update.JobSize, update.JobsUpdatedDaily)

		for i := 0; i < update.JobsUpdatedDaily; i++ {
			service := services[rand.Intn(len(services))]
			service.UpdatesCount++
		}
	}

	return nil
}
