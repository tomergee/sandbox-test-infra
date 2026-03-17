# Design Proposal: Config Propagation & Extreme Concurrency Tuning

## 1. Summary
This proposal focuses on optimizing the Agent Sandbox control plane for high-density, multi-burst scale. It corrects a metadata propagation bug for dynamic pods and severely escalates the controller's worker parallelization capabilities and underlying Kubernetes API rate limits to accommodate hundreds of simultaneous Sandbox requests.

## 2. Motivation
During multiburst load testing, two major bottlenecks emerged in the legacy architecture:
1. **Metadata Desync**: When the `SandboxWarmPool` dynamically generated instances from the template, it failed to specifically inject its unique trackable `poolLabel` onto the spawned pods. This caused the controller to lose track of which child processes belonged to which warm pool.
2. **API Rate Limiting & CPU Starvation**: At 100+ claims per second, the default controller bounds restricted processing to minimal, single-digit parallel worker threads. The client-go limits also defaulted to low QPS bounds (e.g., 20/30). This combination caused the controller to queue operations heavily, introducing artificial latencies and timeout failures across massive bursts.

## 3. Goals & Non-Goals
### Goals
- Ensure dynamically spawned Sandbox pods strictly inherit the specific WarmPool hash identifier label.
- Instrument configurable CLI flags for dynamically controlling worker counts locally per subsystem.
- Instrument configurable CLI flags for managing global `client-go` API QPS and Burst limits.
- Modify the default Helm/Kustomize deployment manifests (`k8s/extensions.controller.yaml`) to run extreme parallelization.

### Non-Goals
- Replacing the standard controller-runtime WorkQueue.
- Implementing predictive auto-scaling of worker threads (they will be statically allocated based on CLI args).

## 4. Proposal / Architecture

### 4.1 Metadata Inheritance
The `SandboxWarmPool` controller will strictly enforce `poolLabel` injection mapping.
1. When iterating over the `SandboxTemplate`, calculate the unique hash: `NameHash(warmPool.Name)`.
2. Explicitly map this identifier to the generated Sandbox's `.Spec.PodTemplate.ObjectMeta.Labels`.
3. This guarantees any child generated from that pool retains a permanent, queryable link back.

### 4.2 CLI Flag Orchestration
We will introduce specific command-line arguments to `main.go` that directly configure the `ctrl.Options{}` block of the Manager.
- `--sandbox-concurrent-workers`
- `--sandbox-claim-concurrent-workers`
- `--sandbox-warm-pool-concurrent-workers`
- `--kube-api-qps`
- `--kube-api-burst`

Inside `SetupWithManager`, each specific controller will absorb its respective worker count config:
`WithOptions(controller.Options{MaxConcurrentReconciles: concurrentWorkers})`

### 4.3 Production Manifest Tuning
Update the hardcoded arguments in `k8s/extensions.controller.yaml`:
```yaml
args:
  # Massive scale parallelization
  - --sandbox-concurrent-workers=300
  - --sandbox-claim-concurrent-workers=300
  - --sandbox-warm-pool-concurrent-workers=300
  - --kube-api-qps=300       # Allow 300 requests per second
  - --kube-api-burst=450     # Allow instant bursts up to 450
```

## 5. Alternatives Considered
- **Defaulting to `runtime.NumCPU()`**: *Rejected* because typical container limits might falsely constrain the available parallelism for entirely I/O bound network heavy API calls. Hardcoded explicitly high numbers yield better queue throughput for Kubernetes API manipulations.

## 6. Implementation Plan
1. Parse flags inside `main.go`.
2. Apply the configuration explicitly to the client config (`config.QPS` and `config.Burst`).
3. Pass the integer values down into the `Reconciler.SetupWithManager` functions.
4. Add the label injection logic to the translation block inside the WarmPool controller.

## 7. Testing & Verification Plan
- **Label Verification**: Deploy a `SandboxWarmPool`. Use `kubectl get sandboxes --show-labels`. Assert every child object possesses the exact pool name hash label.
- **Throttling Verification**: Check the central apiserver logs and the controller logs using the `50x50` multiburst simulation script. Verify the string `Throttling request took...` does not appear.

## 8. Affected Files
- `extensions/controllers/sandboxwarmpool_controller.go`
- `main.go` (Controller manager entrypoint)
- `k8s/extensions.controller.yaml`
