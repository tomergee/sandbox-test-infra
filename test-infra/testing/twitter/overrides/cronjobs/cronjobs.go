// Package cronjobs this is a fake comment.
package cronjobs

import (
	"fmt"
	"sort"
	"strings"

	"gke-internal.googlesource.com/test-infra/perf-tests/testing/twitter/overrides/namespaces"
)

const (
	intervalLimitMins = 30
)

// Spec this is a fake comment.
type Spec struct {
	HealthyCrons []HealthyCron `json:"healthy-crons"`
}

// HealthyCron this is a fake comment.
type HealthyCron struct {
	PartialName   string  `json:"partial_name" yaml:"name"`
	JobCount      int     `json:"job_count" yaml:"jobCount"`
	InstanceCount int     `json:"instance_count" yaml:"instanceCount"`
	Cores         float64 `json:"cores" yaml:"cores"`
	IntervalMins  int     `json:"interval-mins" yaml:"intervalMins"`
	Namespace     int     `yaml:"namespace"`
}

// CanBeCombinedWith returns true iff two HealthyCron instances differ only on the JobCount and can be merged together.
func (hc *HealthyCron) CanBeCombinedWith(cron *HealthyCron) bool {
	return hc.Cores == cron.Cores && hc.InstanceCount == cron.InstanceCount && hc.Namespace == cron.Namespace && hc.PartialName == cron.PartialName && hc.IntervalMins == cron.IntervalMins
}

func appendCron(in []HealthyCron, cron HealthyCron) []HealthyCron {
	if len(in) > 0 {
		last := &in[len(in)-1]
		if last.CanBeCombinedWith(&cron) {
			last.JobCount += cron.JobCount
			return in
		}
	}
	return append(in, cron)
}

func assignNamespaces(spec *Spec, nsDist namespaces.Distribution) error {
	want := nsDist.ToArray()

	sort.Slice(spec.HealthyCrons, func(i, j int) bool {
		return spec.HealthyCrons[i].InstanceCount > spec.HealthyCrons[j].InstanceCount
	})

	ns := 0
	got := 0
	var out []HealthyCron

	for _, spec := range spec.HealthyCrons {
		for i := 0; i < spec.JobCount; i++ {
			if ns < len(want) {
				cron := spec
				cron.JobCount = 1
				cron.Namespace = ns + 1
				out = appendCron(out, cron)
				got += spec.InstanceCount
				if got >= want[ns] {
					ns++
					got = 0
				}
			} else {
				return fmt.Errorf("All %v namespaces have been populated. There is no namespace available for %v", ns, spec.PartialName)
			}
		}
	}

	fmt.Printf("Assigned %d namespaces to %d cronjob types\n", ns+1, len(spec.HealthyCrons))
	spec.HealthyCrons = out
	return nil
}

// Transform this is a fake comment.
// This is mostly copy-paste of microservices.Transform.
// TODO(maciejborsz): Merge them together.
func Transform(spec *Spec, nsDist namespaces.Distribution) error {
	if err := assignNamespaces(spec, nsDist); err != nil {
		return fmt.Errorf("error while assigning namespaces: %v", err)
	}

	coresTotal := 0.0
	jobsTotal := 0
	for i := range spec.HealthyCrons {
		cron := &spec.HealthyCrons[i]
		cron.PartialName = strings.ToLower(cron.PartialName)
		if cron.IntervalMins > intervalLimitMins {
			cron.IntervalMins = intervalLimitMins
		}
		// We simulate 100 cores using 1 core machines.
		cron.Cores /= 100
		coresTotal += cron.Cores * float64(cron.JobCount*cron.InstanceCount)
		jobsTotal += cron.JobCount
	}
	fmt.Printf("Generated %d crons in %d groups and %.2f cores\n", jobsTotal, len(spec.HealthyCrons), coresTotal)
	return nil
}
