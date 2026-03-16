# Base image that includes a shell and common utilities, known to be accessible
FROM marketplace.gcr.io/google/debian12

# Install ca-certificates package to get the update-ca-certificates tool
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy the CA certificates bundle from the original, working image
# This is the standard path for the main CA bundle file.
COPY --from=gcr.io/k8s-staging-perf-tests/perfdash:2.55 /etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates/perfdash-ca-certificates.crt

# Update the system's CA store to include the copied certificates
RUN update-ca-certificates

# Copy the perfdash application and any necessary assets from the original image
COPY --from=gcr.io/k8s-staging-perf-tests/perfdash:2.55 /perfdash /perfdash
COPY --from=gcr.io/k8s-staging-perf-tests/perfdash:2.55 /www /www

# No ENTRYPOINT or CMD is specified here, as the Kubernetes Deployment manifest
# will provide the command to run the startup script (/bin/sh -c /scripts/run_perfdash.sh).
