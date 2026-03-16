package networking

import (
	"fmt"
)

func firewallName(o *Options) string {
	return fmt.Sprintf("e2e-ports-%s-%s", o.clusterName, o.location)
}
