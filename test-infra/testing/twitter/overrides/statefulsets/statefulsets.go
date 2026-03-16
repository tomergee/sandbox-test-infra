// Package statefulsets this is a fake comment.
package statefulsets

import (
	"fmt"
	"os"
)

// Spec this is a fake comment.
type Spec struct {
	Namespace     int `yaml:"namespace"`
	InstanceCount int `yaml:"instanceCount"`
}

// Generate this is a fake comment.
func Generate() ([]Spec, error) {
	ns := 500 // Start with 500 so that it doesn't overlap with stateless services.

	var out []Spec
	total := 0
	// TODO(maciejborsz): Extract those constants to a separate file or parameter.
	for _, size := range []int{2000, 1500, 1400, 1100, 1000, 800, 500, 300} {
		out = append(out, Spec{
			Namespace:     ns,
			InstanceCount: size,
		})
		ns++
		total += size
	}

	fmt.Fprintf(os.Stderr, "Created %d statefulsets with %d pods\n", len(out), total)
	return out, nil
}
