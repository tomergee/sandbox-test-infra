Scalability-image
-----------------

### Description

`gcr.io/gke-scalability-images/scalability-image` is a tiny wrapper on kubekins-e2e image that adds GKE Scalability-specific tools to the image.

### Usage

Simply use `gcr.io/gke-scalability-images/scalability-image:TAG` as an image for prow job.

### Building

`$ make push-image BRANCH=main`
