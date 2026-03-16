Scalability-image
-----------------

### Description

`gcr.io/gke-scalability-images/scalability-image` is a tiny wrapper on perfdash image that adds bash to the image.

### Usage

Simply use `gcr.io/gke-scalability-images/sts-perfdash:TAG` as an image for prow job.

### Building

`$ make push-image BRANCH=main`
