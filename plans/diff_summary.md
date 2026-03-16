# Diff Summary: Local vs Remote (origin/main)

This document summarizes the changes in the local working directory `/usr/local/google/home/glottman/dev/jetski_main/branches/sandboxclaim-perf-improvements` compared to `origin/main`.

## Overview

The local changes represent a significant refactor to manage `Sandbox` resources directly, moving away from legacy `Pod`-based management. This includes the deletion of legacy configuration files and a complete overhaul of the `SandboxClaim` and `SandboxWarmPool` controllers.

### Statistics
- **Files Changed**: 56
- **Insertions**: 859
- **Deletions**: 3445

## Key Changes

### 1. Resource Management Shift (Naked Pods to Sandboxes)
- The system now exclusively manages `Sandbox` custom resources instead of `Pod` resources.
- RBAC permissions have been updated to include `sandboxes`.
- `k8s/controller.yaml` has been **deleted**.

### 2. SandboxClaim Controller Refactor
- **Deterministic Adoption**: Implements a FIFO-based, deterministic algorithm for adopting `Sandboxes` from the `WarmPool`. It uses a search window based on the claim's UID to prevent multiple claims from racing to adopt the same sandbox (solving the "Thundering Herd" problem).
- **Status Patching**: Consistently uses `Patch` instead of `Update` for status updates, reducing conflicts.
- **Metrics**: Introduces `SandboxClaimReadyLatency` for better performance tracking.
- **Concurrency**: Added `MaxConcurrentReconciles` configuration.

### 3. SandboxWarmPool Controller Refactor
- **Sandbox Pool & Abstraction**: The WarmPool controller now maintains a pool of `v1alpha1.Sandbox` Custom Resources instead of managing raw Kubernetes `Pod` resources directly. 
- **Delegated Provisioning**: By outputting `Sandbox` resources (carrying the pool's label and specs from the `SandboxTemplate`), it delegates the actual underlying Pod creation to the core `Sandbox` controller. When a `SandboxClaim` comes in, it just adopts that pre-warmed `Sandbox` object.
- **Template propagation**: Propagates configuration from `SandboxTemplate` down to the `Sandbox` spec.
- **Status Patching**: Also uses `Patch` for status updates.

### 4. Performance Configurations
- `k8s/extensions.controller.yaml` has been updated with significantly increased concurrency settings (`--sandbox-*concurrent-workers=300`) and API limits (`--kube-api-qps/burst=300/450`).

### 5. Deleted Legacy Code
- `extensions/controllers/sandboxtemplate_controller.go` (and tests) appear to have been deleted or heavily modified (diff stat shows 221 deletions).
- `extensions/examples/llm.yaml` deleted.

## Git Info
- **Current Commit**: `67e86b2 Improve sandboxclaim controller management of multiple worker threads` (Local)
- **Base Commit**: `1033d1b controllers/sandbox_controller: add RBAC for finalizers (#377)` (Origin)

## Missing the `load-test.sh`
- The `load-test.sh` script was not found in the source configs directory during repository creation.
