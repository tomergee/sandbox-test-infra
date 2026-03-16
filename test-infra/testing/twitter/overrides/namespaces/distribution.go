// Package namespaces this is a fake comment.
package namespaces

// Spec this is a fake comment.
type Spec struct {
	Secrets  Distribution
	Services Distribution
	Cronjobs Distribution
}

// Namespace this is a fake comment.
type Namespace struct {
	Count int
	Size  int
}

// Distribution this is a fake comment.
type Distribution []Namespace

// ToArray this is a fake comment.
func (d *Distribution) ToArray() []int {
	var out []int
	for _, ns := range *d {
		for i := 0; i < ns.Count; i++ {
			out = append(out, ns.Size)
		}
	}
	return out
}
