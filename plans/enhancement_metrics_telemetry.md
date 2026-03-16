# Enhancement: Metric Enhancements & Granular Log Instrumentation

## Background & Goal
While basic lifecycle tracking exists within the controllers, our current telemetry makes it difficult to dissect edge-case latency spikes during massive bursts. Specifically, measuring the precise time between a `SandboxClaim` being created and its adoption to a `Ready` state is critical piece of the load-test verification stack, and the original code makes parsing this log-by-log almost impossible.

This enhancement fortifies our observability pillar by tracking the exact state transition matrix (from "Pending" -> "Ready") and broadcasting `SandboxClaimReadyLatency` both to the remote prometheus node and natively to standard output via tightly structured logging logic.

## Implementation Plan
1. **Instrument Prometheus Metric**: 
   - Expose the exact duration in seconds using the `SandboxClaimReadyLatency` gauge variable inside the `sandboxclaim_controller.go`. 
2. **Implement Tightly Structured MS Log Traces**: 
   - Before exposing to Prometheus, calculate the exact completion time from object `CreationTimestamp`.
   - Add a strictly formatted output that exposes the latency calculation in milliseconds: `SandbClaimReadyMS` to standard out. This simplifies our local Python scripts.
3. **De-duplicate Metric Exporting**: 
   - Emitting metrics during reconciliation has a fatal flaw: Kubernetes loops can re-trigger repeatedly even after an object hits `Ready`, which would artificially overwrite the latency score with increasingly huge durations over time.
   - Add a fast memory cache via `sync.Map` (e.g., `readyClaims := sync.Map{}`) to register uncounted claims.
   - During reconciliation, check this cache structure. Only calculate and broadcast latency exactly once per `SandboxClaim` transition.

## Success Criteria
- End-to-end load testing easily aggregates P50/P90/P99 curves from structured `.log` scraping.
- The Prometheus `/metrics` endpoint broadcasts the latest burst aggregates without overwrites natively.
- No memory leaks are introduced into the controller tracking map.
