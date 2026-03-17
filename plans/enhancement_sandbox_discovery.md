# Design Proposal: Robust Sandbox Discovery & Adoption

## 1. Summary
The `SandboxClaim` controller must transition from adopting raw `v1.Pod` instances to managing and adopting higher-order `v1alpha1.Sandbox` Custom Resources. This proposal outlines a robust, 5-stage discovery algorithm resilient to high-concurrency desyncs (e.g., split-brain, missed cache updates) to solve the "Thundering Herd" problem during multiburst load testing.

## 2. Motivation
Currently, the `SandboxClaim` controller searches for and adopts raw `Pod` instances directly from the `SandboxWarmPool` via helper methods like `getOrCreatePod`. This bypasses the actual `Sandbox` Custom Resource abstraction that Agent Sandbox relies on for holistic lifecycle management.

Furthermore, during extreme scaling (e.g., 50+ claims simultaneously), cache propagation lag causes the controller to frequently "lose" track of newly spawned resources. Multiple parallel reconciliation threads might fail to see an existing allocation, causing them to all spawn duplicate resources simultaneously. This wastes cluster compute and triggers API server throttling. We need a deterministic, conflict-free way to discover and adopt `Sandbox` resources.

## 3. Goals & Non-Goals
### Goals
- Fully migrate `sandboxclaim_controller.go` to adopt `v1alpha1.Sandbox` objects, abandoning raw Pod manipulation.
- Implement a foolproof, multi-stage Sandbox discovery pipeline that survives controller cache desyncs.
- Gracefully handle orphaned Sandboxes (objects that exist but lost their `OwnerReferences` to the Claim).
- Prevent duplicate Sandbox creation under heavy load.

### Non-Goals
- Redesigning the underlying Pod creation logic (which remains delegated to the core `Sandbox` controller).
- Changing the `SandboxWarmPool` scaling heuristics.

## 4. Proposal / Architecture
We propose replacing `getOrCreatePod` with a heavily fortified parent abstraction: `getOrCreateSandbox`. This function will execute a strict 5-stage cascade to definitively locate an assigned Sandbox before ever attempting to create a new one.

### The 5-Stage Discovery Cascade
1. **Stage 1 (Status Fast-Path)**: Immediately check `sandboxClaim.Status.SandboxName`. If populated, fetch explicitly by name.
2. **Stage 2 (GUID Label Search - The Safety Net)**: Execute a Label Selector search querying the cluster for any `Sandbox` possessing a dynamic `SandboxIDLabel` matching the specific `SandboxClaim` UID. 
   - *Self-Healing Recovery*: If a matching Sandbox is found but its `OwnerReferences` are missing or corrupted, the controller will dynamically patch the `OwnerReferences` back onto the Sandbox, reclaiming the orphaned object.
3. **Stage 3 (Name Fallback)**: Attempt to fetch a Sandbox strictly matching the name of the `SandboxClaim` to support legacy static-naming assumptions.
4. **Stage 4 (WarmPool Adoption)**: Execute `tryAdoptSandboxFromPool`. This queries the `SandboxWarmPool` for any available, unassigned pre-warmed Sandbox. We must employ a collision-resistant deterministic selection (e.g., FIFO or specific sorting) so multiple concurrent claims don't adopt the *same* pre-warmed Sandbox.
5. **Stage 5 (Fresh Creation)**: If Stages 1-4 return nil, and only then, gracefully fallback to generating a brand new `v1alpha1.Sandbox` resource and assigning it the `SandboxClaim` UID label to close the loop.

## 5. Alternatives Considered
- **Pessimistic Locking**: Locking adoption using distributed Redis locks or Leases. *Rejected* due to massive architectural overhead and performance bottlenecks.
- **Relying solely on Status Updates**: *Rejected* because API server drops and cache lag frequently cause the Status to trail behind actual cluster state in bursts. The Label Search (Stage 2) is mandatory for eventual consistency.

## 6. Implementation Plan
1. Deprecate and remove all functions analogous to `getOrCreatePod` inside `sandboxclaim_controller.go`.
2. Introduce the `getOrCreateSandbox` cascade as described.
3. Update RBAC manifests to ensure the controller has robust `get`, `list`, `watch`, `create`, `update`, `patch`, `delete` permissions explicitly on `sandboxes` and `sandboxes/status`.

## 7. Testing & Verification Plan
- **Unit Tests**: Inject mock clients simulating split-brain (where a Sandbox exists with the correct GUID label but no OwnerReference) and assert the controller patches the ownership rather than creating a duplicate.
- **E2E Multiburst Test**: Execute `test-e2e.sh` and a 100-node 10 QPS burst test. Verify via controller logs and Prometheus that the number of `Sandbox` objects created exactly matches the number of `SandboxClaims`, proving the Thundering Herd is mitigated.

## 8. Affected Files
- `extensions/controllers/sandboxclaim_controller.go`
- `extensions/controllers/sandboxclaim_controller_test.go`
