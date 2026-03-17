# Design Proposal: Metric Enhancements & Granular Log Instrumentation

## 1. Summary
This proposal aims to fortify the observability of the `SandboxClaim` lifecycle. By explicitly calculating the end-to-end `Ready` latency of a claim, we can expose both a Prometheus gauge (`SandboxClaimReadyLatency`) and a strictly formatted millisecond log trace (`SandbClaimReadyMS: X`), ensuring accurate telemetry during load-test verifications.

## 2. Motivation
During multiburst load testing, verifying the performance of the warm pool and adoption algorithms is paramount. Currently, measuring the precise time between a `SandboxClaim` creation and its transition to a `Ready` state requires parsing fragmented controller logs or guessing bounds. 

Furthermore, emitting metrics natively inside a Kubernetes reconciliation loop (`Reconcile`) is dangerous. If a `SandboxClaim` hits `Ready`, it might still be re-queued later for unrelated reasons (e.g., label updates). If the metric calculation simply fires every time `Ready` is observed, it will artificially inflate the latency calculation using the current clock time versus the original creation time, overwriting the legitimate initial burst latency score.

## 3. Goals & Non-Goals
### Goals
- Extract exact latency timing from `SandboxClaim` creation to `Ready` status.
- Expose the latency calculation in seconds natively to Prometheus via the `/metrics` endpoint.
- Expose the latency calculation in milliseconds to standard out for external scraping scripts.
- Implement strict de-duplication so a claim's latency is calculated and exported exactly *once*.

### Non-Goals
- Adding tracing spans (like Jaeger/OpenTelemetry) to the core controller logic.
- Building custom Grafana dashboards within this specific PR.

## 4. Proposal / Architecture
### 4.1 Telemetry Exposure
1. **Prometheus Gauge**: Implement a standard prometheus `GaugeVec` variable, `SandboxClaimReadyLatency`, tagged by Namespace and Pool.
2. **Log Structure**: Emit `klog.Infof("SandboxClaim %s become ready, SandbClaimReadyMS: %d", claim.Name, latency.Milliseconds())`.

### 4.2 State Transition & De-duplication
To solve the re-queue overwrite issue, the controller requires local state management.
1. Implement a controller-level cache: `readyClaims sync.Map`.
2. Inside `Reconcile`:
   - If `claim.Status.Phase == "Ready"`:
     - Check `readyClaims.Load(claim.UID)`.
     - If it exists, skip all metric calculations (it was already processed).
     - If it does *not* exist:
       - Calculate `time.Since(claim.CreationTimestamp.Time)`.
       - Broadcast to Prometheus.
       - Log the `SandbClaimReadyMS` trace.
       - Store the UID in `readyClaims.Store(claim.UID, true)`.

## 5. Alternatives Considered
- **Updating the Claim Status with Latency**: Storing the latency directly in `SandboxClaim.Status.AdoptionLatency`. *Rejected* as it adds unnecessary write-load to the API server during bursts just for telemetry.
- **Relying solely on kube-state-metrics**: *Rejected* because state-metric polling intervals (typically 15-30s) are far too course to capture the sub-second/millisecond adoption speeds of our warm pool.

## 6. Implementation Plan
1. Initialize the Prometheus metric variables globally in the metrics package.
2. Inject the `sync.Map` into the `SandboxClaimReconciler` struct.
3. Write the transition trap inside the core loop to catch the first `Ready` flip.

## 7. Testing & Verification Plan
- **Duplicate Prevention Test**: Write a unit test that mocks a `SandboxClaim` transitioning to `Ready`, forces a manual requeue of the same object 5 seconds later, and asserts the metric incremented/fired only once.
- **Log Scraping Verification**: Run a mini burst (10 claims) and ensure a Python regex parser can successfully trap exactly 10 instances of `SandbClaimReadyMS`.

## 8. Affected Files
- `internal/metrics/metrics.go`
- `extensions/controllers/sandboxclaim_controller.go`
