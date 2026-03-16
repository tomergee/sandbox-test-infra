package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"gke-internal.googlesource.com/test-infra/perf-tests/karchive/pkg/kaas"
)

var (
	rootCmd = &cobra.Command{}

	dumpData = &cobra.Command{
		Use:   "dump-data",
		Short: "Dumps auxiliary debugging links to the Prow job's artifacts and IP addresses",
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := DumpData(); err != nil {
				return fmt.Errorf("error while dumping data: %w", err)
			}
			return nil
		},
	}

	internalIpsOutput string
	publicIpsOutput   string
	name              string
	location          string
	project           string
	hash              string

	refreshLinks = &cobra.Command{
		Use:   "refresh-links",
		Short: "Refresh timestamps in the previously dumped auxiliary debugging links",
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := RefreshDebuggingLinks(); err != nil {
				return fmt.Errorf("error while refreshing debugging links: %w", err)
			}
			return nil
		},
	}
)

func DumpData() error {
	runInfo, err := kaas.CreateRunInfo(name, location, project, hash)
	if err != nil {
		return fmt.Errorf("error while creating the run info: %w", err)
	}
	var errs []error
	if internalIpsOutput != "" {
		if err := runInfo.DumpInternalIps(internalIpsOutput); err != nil {
			errs = append(errs, fmt.Errorf("error while dumping internal IP addresses: %w", err))
		}
	}
	if publicIpsOutput != "" {
		if err := runInfo.DumpPublicIps(publicIpsOutput); err != nil {
			errs = append(errs, fmt.Errorf("error while dumping public IP addresses: %w", err))
		}
	}
	if err := runInfo.DumpKarchiveData(); err != nil {
		errs = append(errs, fmt.Errorf("error while dumping karchive data: %w", err))
	}
	runInfo.DumpLinks()
	if err := runInfo.DumpComponentsVersions(); err != nil {
		errs = append(errs, fmt.Errorf("error while dumping components versions: %w", err))
	}
	if len(errs) > 0 {
		return fmt.Errorf("DumpData failed with the following errors: %v", errs)
	}
	return nil
}

func RefreshDebuggingLinks() error {
	runInfo, err := kaas.GetKarchiveData()
	if err != nil {
		return fmt.Errorf("error while retrieving the run info from artifacts: %w", err)
	}
	runInfo.DumpLinks()
	return nil
}

func init() {
	rootCmd.AddCommand(dumpData)
	rootCmd.AddCommand(refreshLinks)
	dumpData.Flags().StringVarP(&internalIpsOutput, "internal-ips-output", "o", "", "Path to file where internal IP addresses will be saved")
	dumpData.Flags().StringVarP(&publicIpsOutput, "public-ips-output", "", "", "Path to file where public IP addresses will be saved")
	dumpData.Flags().StringVarP(&name, "cluster-name", "", "", "Cluster name")
	dumpData.Flags().StringVarP(&location, "location", "", "", "Zone or region")
	dumpData.Flags().StringVarP(&project, "project", "", "", "Project")
	dumpData.Flags().StringVarP(&hash, "hash", "", "", "Cluster hash")
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: problem with handling debugging links: %v\n", err)
		os.Exit(1)
	}
}
