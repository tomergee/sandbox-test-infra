# Enhancement: Robust Sandbox Discovery & Adoption (SandboxClaim Controller)

## Background & Goal
Currently, the `SandboxClaim` controller searches for and adopts raw `Pod` instances directly from the `SandboxWarmPool` (via functions like `getOrCreatePod`). This legacy mode relies on pods, completely bypassing the higher-order Custom Resource (`v1alpha1.Sandbox`) intended for lifecycle management.

This enhancement completely remodels the adoption algorithm to target fully populated `v1alpha1.Sandbox` objects instead of naked Pods. It introduces a heavily fortified, 5-stage discovery search to prevent states desyncs that occur during burst scaling or API server lag where a Sandbox is "lost" or left dangling.

## Implementation Plan
1. **Deprecate `getOrCreatePod`**: Replace all occurrences and associated algorithms relying on `getOrCreatePod` inside `sandboxclaim_controller.go`.
2. **Implement `getOrCreateSandbox`**: Design a new parent abstraction that adopts the entire `v1alpha1.Sandbox` object.
3. **Resilient 5-Stage Discovery Pipeline**: Implement the following strict fallback order inside `getOrCreateSandbox` to fetch a Sandbox safely:
   - **Stage 1 (Status Check)**: Fast-path. Check if the `SandboxClaim` Status already possesses a recorded Sandbox reference. Return if true.
   - **Stage 2 (GUID Label Search)**: Execute a Label Selector search looking for a Sandbox carrying the specific `SandboxIDLabel` matching the `SandboxClaim` UID. 
     - *Crucial Error Recovery*: If a Sandbox is found via GUID but is missing its `OwnerReferences` (due to split-brain or lag), dynamically **restore ownership** via patching to reclaim the orphaned object.
   - **Stage 3 (Name Fallback)**: Attempt to fetch a Sandbox strictly matching the name of the `SandboxClaim` (handling legacy direct-name assumptions).
   - **Stage 4 (WarmPool Adoption Algorithm)**: Execute the `tryAdoptSandboxFromPool` strategy to securely pluck an available, unassigned pre-warmed Sandbox from a matching `SandboxWarmPool`.
   - **Stage 5 (Fresh Creation)**: If all discovery avenues are exhausted, generate a brand new `v1alpha1.Sandbox` custom resource on-demand.

## Success Criteria
- The controller never attempts to look up or manage a raw `v1.Pod`.
- The `SandboxClaim` successfully survives rapid desyncs without causing "thundering herd" duplicate creations.
- Unit tests pass proving the 5-stage resilient discovery process prioritizes pre-existing allocations accurately.
