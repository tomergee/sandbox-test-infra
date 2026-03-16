BRANCH ?= main
BASEIMAGE ?= us-central1-docker.pkg.dev/k8s-staging-test-infra/images/kubekins-e2e:latest-master

PROJECT ?= gke-scalability-images
IMG ?= scalability-image-kubetest2
TAG ?= $(shell date +v%Y%m%d)-$(shell git describe --tags --always --dirty)-$(BRANCH)


TEST_INFRA_ROOT := $(shell git rev-parse --show-toplevel)

.PHONY: create-image
create-image:
	gcloud auth configure-docker
	docker build -t $(IMG):$(TAG) -t $(IMG):latest-$(BRANCH) -f Dockerfile --build-arg BASEIMAGE=$(BASEIMAGE) $(TEST_INFRA_ROOT)/perf-tests

.PHONY: update-image
update-image:
	gcloud auth configure-docker
	docker tag $(IMG):$(TAG) gcr.io/$(PROJECT)/$(IMG):$(TAG)
	docker tag $(IMG):$(TAG) gcr.io/$(PROJECT)/$(IMG):latest-$(BRANCH)
	docker push gcr.io/$(PROJECT)/$(IMG):$(TAG)
	docker push gcr.io/$(PROJECT)/$(IMG):latest-$(BRANCH)

.PHONY: push-image
push-image: create-image update-image
