# Diff Summary: Local vs Remote Branch (`igooch/sandboxclaim-perf`)

This document summarizes the changes in the local working directory `/usr/local/google/home/glottman/dev/jetski_main/branches/sandboxclaim-perf-improvements` compared to the remote branch `igooch/sandboxclaim-perf` (the PR branch).

## Overview

The structural difference between the local branch and `igooch/sandboxclaim-perf` is significant. The remote branch manages and emits raw Kubernetes `Pod` resources across all its controllers (from SandboxClaim to SandboxWarmPool). In contrast, the local copy introduces a profound architectural shift: managing full `v1alpha1.Sandbox` Custom Resources. 

On top of this Custom Resource transition, the local copy also introduces massive robustness, conflict-free state reconciliation, and performance improvements to handle multiburst scenarios accurately.

### Statistics
- **Files Changed**: 41
- **Insertions**: 768
- **Deletions**: 2621

## Key Local Improvements Over the Remote Branch

### 1. Robust Sandbox vs Pod Discovery & Adoption
In the remote branch, the `SandboxClaim` controller searches for and adopts raw `Pod` instances from the `SandboxWarmPool` (e.g., using `getOrCreatePod`). The local branch completely abandons this approach:
- **`getOrCreateSandbox` Replacment**: The controller is now designed to discover and adopt fully populated `v1alpha1.Sandbox` objects instead of Pods.
- **Resilient Discovery Strategy**:
  1. **Status Check**: First tries returning the sandbox listed in the claim's status.
  2. **GUID Label Search**: Searches for a sandbox carrying the `SandboxIDLabel` matching the claim's UID. Crucially, if it finds a sandbox that lost owner references, it will dynamically **restore ownership** via patching.
  3. **Claim Name Fallback**: Tries fetching a sandbox with the same name as the claim.
  4. **WarmPool Adoption**: Executes the `tryAdoptSandboxFromPool` strategy to securely pluck a pre-warmed Sandbox.
  5. **Fresh Creation**: Falls back to creating a new Sandbox resource.

### 2. Conflict-Free Status Updates
Across the controllers (`sandbox_controller.go`, `sandboxclaim_controller.go`, `sandboxwarmpool_controller.go`), the status update mechanism was refactored.
- **Removed**: Direct `Status().Update(ctx, obj)` which often causes "object has been modified" errors.
- **Added**: Best-practice patching. The controllers now fetch the absolute latest version of the object, apply the new status to a copy, and issue a `client.MergeFrom` patch `Status().Patch(ctx, latestObj, patch)`. This handles high-concurrency races elegantly.

### 3. Metric Enhancements
- Properly tracks state transitions (from not-ready to ready) to emit the `SandboxClaimReadyLatency` in seconds to Prometheus.
- Explicitly logs `SandbClaimReadyMS` in milliseconds to the controller logs for fine-grained log-based parsing.
- Uses `sync.Map` (`readyClaims`) to prevent double-counting latencies across reconciliation loops.

### 4. Network Policy Reconciliation
- Added `reconcileNetworkPolicy` into the SandboxClaim lifecycle. It correctly applies network policies based on the `SandboxTemplate` or actively cleans up/deletes existing `NetworkPolicy` resources if the template disables them.

### 5. Config Propagation & Deep Tuning
- `SandboxWarmPool` now correctly propagates the `poolLabel` down into the `sandbox.Spec.PodTemplate.ObjectMeta.Labels` to assure that the actual dynamically spawned pods can be matched back.
- Heavy tuning of concurrency settings within `k8s/extensions.controller.yaml`:
  - `--sandbox-concurrent-workers=300`
  - `--sandbox-claim-concurrent-workers=300`
  - `--sandbox-warm-pool-concurrent-workers=300`
  - Increased QPS & Burst to `300`/`450`.

## Git Info
- **Comparison base**: Branch `igooch/sandboxclaim-perf` (`209a096 Adds unit tests`)
- **Local HEAD**: `67e86b2 Improve sandboxclaim controller management of multiple worker threads`
