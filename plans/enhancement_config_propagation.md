# Enhancement: Config Propagation & Extreme Concurrency Tuning

## Background & Goal
During large scale multiburst testing, simply instantiating a large number of Pods via the WarmPool controller frequently hit hard ceilings due to API server rate limits and single-threaded worker bottlenecks. Further, metadata like pool labels did not correctly propagate from the parent pool down to dynamically spawned pods, causing tracking desyncs.

This enhancement tunes the core processing loops of all Sandbox controllers, heavily scaling their parallelism parameters and ensuring strictly inherited configuration flow down the object hierarchy.

## Implementation Plan
1. **Fix `poolLabel` Propagation**:
   - Ensure `SandboxWarmPool` explicitly injects `poolLabel: $hash` into the `sandbox.Spec.PodTemplate.ObjectMeta.Labels` payload when cloning the `SandboxTemplate`.
   - This prevents pods from accidentally orchestrating themselves outside the scope of their designated warm pool.
2. **Expose MaxConcurrentReconciles Config**:
   - Introduce explicitly named CLI flags for each subsystem within the main controller logic:
     - `--sandbox-concurrent-workers`
     - `--sandbox-claim-concurrent-workers`
     - `--sandbox-warm-pool-concurrent-workers`
3. **Elevate Global API Interaction Limits**:
   - Expand the controller's underlying client-go interaction budget. 
   - Expose `--kube-api-qps` and `--kube-api-burst` via CLI flags.
4. **Deploy Massive Aggressive Tunings**:
   - Modify the default deployment config inside `k8s/extensions.controller.yaml` to run at production-scale concurrency.
   - Ramp workers to `300` per subsystem.
   - Expand client QPS bounds to `300` and Burst thresholds to `450`.

## Success Criteria
- Sustained high API-hit adoption bursts complete rapidly instead of rate-limiting or freezing.
- Dynamic pods properly inherit the pool hash identifier at creation.
