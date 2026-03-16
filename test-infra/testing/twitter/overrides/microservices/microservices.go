// Package microservices this is a fake comment.
package microservices

import (
	"fmt"
	"reflect"
	"sort"
	"strings"

	"gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/namespaces"
)

// Spec this is a fake comment.
type Spec struct {
	HealthyServices []HealthyService `json:"healthy-services"`
}

// HealthyService this is a fake comment.
type HealthyService struct {
	PartialName   string  `json:"partial_name" yaml:"name"`
	JobCount      int     `json:"job_count" yaml:"jobCount"`
	InstanceCount int     `json:"instance_count" yaml:"instanceCount"`
	Cores         float64 `json:"cores" yaml:"cores"`
	Namespace     int     `yaml:"namespace"`
	UpdatesCount  int     `yaml:"updatesCount"`
	Secrets       []int   `yaml:"secrets,flow"`
}

// CanBeCombinedWith returns true iff two HealthyService instances differs only on JobCount,
// so it is possible to merge them together.
func (hs *HealthyService) CanBeCombinedWith(service *HealthyService) bool {
	return hs.Cores == service.Cores && hs.InstanceCount == service.InstanceCount && hs.Namespace == service.Namespace && hs.PartialName == service.PartialName && hs.UpdatesCount == service.UpdatesCount && reflect.DeepEqual(hs.Secrets, service.Secrets)
}

// JobSize this is a fake comment.
func (hs *HealthyService) JobSize() string {
	return fmt.Sprintf("%d-replica", hs.InstanceCount)
}

func appendService(in []HealthyService, service HealthyService) []HealthyService {
	if len(in) > 0 {
		last := &in[len(in)-1]
		if last.CanBeCombinedWith(&service) {
			last.JobCount += service.JobCount
			return in
		}
	}
	return append(in, service)
}

func assignNamespaces(spec *Spec, nsDist namespaces.Distribution) error {
	want := nsDist.ToArray()

	sort.Slice(spec.HealthyServices, func(i, j int) bool {
		return spec.HealthyServices[i].InstanceCount > spec.HealthyServices[j].InstanceCount
	})

	ns := 0
	got := 0
	var out []HealthyService

	for _, spec := range spec.HealthyServices {
		for i := 0; i < spec.JobCount; i++ {
			if ns < len(want) {
				service := spec
				service.JobCount = 1
				service.Namespace = ns + 1
				out = appendService(out, service)
				got += spec.InstanceCount
				if got >= want[ns] {
					ns++
					got = 0
				}
			} else {
				return fmt.Errorf("unable to assign NS to service of size %v", spec.InstanceCount)
			}
		}
	}

	fmt.Printf("Assigned %d namespaces to %d service types\n", ns+1, len(spec.HealthyServices))
	spec.HealthyServices = out
	return nil
}

// Transform this is a fake comment.
func Transform(spec *Spec, nsDist namespaces.Distribution) error {
	if err := assignNamespaces(spec, nsDist); err != nil {
		return fmt.Errorf("error while assigning namespaces: %v", err)
	}

	coresTotal := 0.0
	jobsTotal := 0
	instancesTotal := 0
	for i := range spec.HealthyServices {
		spec := &spec.HealthyServices[i]
		spec.PartialName = strings.ToLower(spec.PartialName)
		// We simulate 100 cores using 1 core machines.
		spec.Cores /= 100
		coresTotal += spec.Cores * float64(spec.JobCount*spec.InstanceCount)
		jobsTotal += spec.JobCount
		instancesTotal += spec.InstanceCount * spec.JobCount
	}

	fmt.Printf("Created %d microservices (in %d groups) with %d pods and %.2f cores\n", jobsTotal, len(spec.HealthyServices), instancesTotal, coresTotal)
	return nil
}
