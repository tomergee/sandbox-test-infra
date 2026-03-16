package boskos

import (
	"context"
	"log"
	"os"
	"time"

	"sigs.k8s.io/boskos/client"

	"gke-internal.googlesource.com/test-infra/perf-tests/tftest/pkg/config"
)

const (
	BoskosURL = "http://boskos.test-pods.svc.cluster.local."
)

var (
	boskos *client.Client
)

func InitClient(jobName string) error {
	var err error
	boskos, err = client.NewClient(jobName, BoskosURL, "", "")
	return err
}

func PrepareProject(o *config.TftestOptions) error {
	if len(o.BoskosPool) == 0 {
		log.Printf("Using project %q outside of Boskos", o.Project)
		return nil
	}
	log.Printf("Initializing the Boskos client")
	if err := InitClient(os.Getenv("JOB_NAME")); err != nil {
		log.Printf("Failed to initialize the Boskos client: %v", err)
		return err
	}
	log.Printf("Initialized the Boskos client")

	log.Printf("Trying to acquire a GCP project from the Boskos pool %q", o.BoskosPool)
	ctx, cancel := context.WithTimeout(context.Background(), o.BoskosWaitDuration)
	defer cancel()
	project, err := AcquireProject(ctx, o.BoskosPool)
	if err != nil {
		log.Printf("Failed to acquire the project: %v", err)
		return err
	}
	o.Project = project
	if project == "gke-scalability-megacluster" {
		o.Location = "us-central1"
	} else if project == "gke-scalability-cluster-65k-1" {
		o.Location = "us-east1"
	}
	log.Printf("Acquired project %q from Boskos", project)

	return nil
}

func AcquireProject(ctx context.Context, pool string) (string, error) {
	project, err := boskos.AcquireWait(ctx, pool, "free", "busy")
	if err != nil {
		return "", err
	}
	go func(c *client.Client, proj string) {
		for range time.Tick(time.Minute * 5) {
			if err := c.UpdateOne(project.Name, "busy", nil); err != nil {
				log.Printf("[Boskos] Update of %s failed with %v", project.Name, err)
			}
		}
	}(boskos, project.Name)

	return project.Name, nil
}

func ReleaseResources() error {
	return boskos.ReleaseAll("dirty")
}

func HasResource() bool {
	if boskos != nil {
		return boskos.HasResource()
	} else {
		log.Println("[Boskos] No client, not possible to acquire resource")
	}
	return false
}
