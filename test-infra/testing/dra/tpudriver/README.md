YAML files has been created using https://source.corp.google.com/h/gke-internal/kubernetes/tpu-dra-driver/+/master:README.md;bpv=1

Following the instruction please set

```
${DRIVER_IMAGE_REGISTRY:="gcr.io/gke-scalability-images/tpu-dra"}
${DRIVER_IMAGE_TAG:=${NEXT_VERSION}
```

Call:

```
./hack/build-driver.sh
```

Then call:

```
helm template tpu-dra-driver ${PROJECT_DIR}/deployments/helm/tpu-dra-driver \
  --namespace tpu-dra-driver \
  --set image.repository=${DRIVER_IMAGE_REGISTRY}/${DRIVER_IMAGE_NAME} \
  --set image.tag=${DRIVER_IMAGE_TAG} \
  --set image.pullPolicy=Always \
  --set cdi.enabled=true \
  --set cdi.default=true \
  --set controller.priorityClassName="" \
  --set kubeletPlugin.priorityClassName="" \
  --set 'deviceClasses={tpu}' \
  --set 'kubeletPlugin.tolerations[0].key=google.com/tpu' \
  --set 'kubeletPlugin.tolerations[0].operator=Exists' \
  --set 'kubeletPlugin.tolerations[0].effect=NoSchedule' > tpu-dra-driver-manifests.yaml
```

Modify tpu-dra-driver-kubeletplugin to reflect new image address. Update YAMLs here based on `tpu-dra-driver-manifests.yaml`.
