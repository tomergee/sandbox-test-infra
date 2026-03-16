Scalability-image-kubetest2
---------------------------

### Description

`gcr.io/gke-scalability-images/scalability-image-kubetest2` is a tiny wrapper on kubekins-e2e-v2 image that adds GKE Scalability-specific tools to the image.

### Usage

Simply use `gcr.io/gke-scalability-images/scalability-image-kubetest2:TAG` as an image for prow job.

### Building

`$ make push-image BRANCH=main`
