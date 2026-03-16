# Agent Sandbox Test Infrastructure

This repository contains everything needed to test a version of the agent-sandbox controller benchmarks.

## Repository Structure

- `clusterloader2/`: Containing the `clusterloader2` tool (source and binary).
- `configs/`: Containing the benchmark configuration files (`*.yaml`) and templates.
- `docs/`: Documentation.
- `templates/`: Templates for reports.
- `run-load-test.sh`: Helper script to run tests.

## Prerequisites

1.  **Kubernetes Cluster**: You need a running Kubernetes cluster.
2.  **Agent Sandbox Controller**: The controller and CRDs must be installed on the cluster.
3.  **Kubeconfig**: You need a valid `kubeconfig` file configured to access your cluster.

## Running the Benchmarks

You can run the benchmarks using the `run-load-test.sh` script or directly using `clusterloader2`.

### Using `run-load-test.sh`

This script provides a convenient way to run tests with default parameters.

```bash
./run-load-test.sh [config-name] [provider]
```

- **`config-name`**: The name of the configuration file in `configs/` (e.g., `agent-sandbox-warmpool-load-test.yaml`). Defaults to `agent-sandbox-warmpool-load-test.yaml`.
- **`provider`**: The Kubernetes provider (e.g., `gke`, `kind`). Defaults to `gke`.

**Example:**

```bash
./run-load-test.sh agent-sandbox-warmpool-load-test.yaml gke
```

### Using `clusterloader2` Directly

For more advanced options, you can run `clusterloader2` directly.

```bash
./clusterloader2/clusterloader2 \
  --testconfig=configs/agent-sandbox-warmpool-load-test.yaml \
  --kubeconfig=$HOME/.kube/config \
  --provider=gke
```

## Available Configurations

- `agent-sandbox-load-test.yaml`: Standard load test (No warm pool).
- `agent-sandbox-warmpool-load-test.yaml`: Load test with warm pool.
- `agent-sandbox-warmpool-multiburst.yaml`: Multiburst load test.

## Verification

Results are saved in `clusterloader2/junit.xml` (or equivalent location if overridden).
You can analyze the results using the provided scripts (if any) or manually.

## Documentation

- `docs/adding_latency_logging.md`: Guide on adding latency logging to the controller.
- `templates/benchmark-report-template.md`: Template for reporting results.
