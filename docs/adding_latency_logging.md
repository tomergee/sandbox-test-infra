# Adding Latency Logging to SandboxClaim Controller

To get benchmark results (latency metrics) in any new branch of the sandboxclaim controller, you must ensure that the `SandbClaimReadyMS` metric is being recorded.

If you are working with a clean branch that doesn't have this logging, follow these steps to add it.

## 1. Locate the Reconcile Function
Open `extensions/controllers/sandboxclaim_controller.go` (or equivalent).

## 2. Check for `recordCreationLatencyMetric`
Look for a function `recordCreationLatencyMetric` or similar. If it doesn't exist, you will need to implement it.

## 3. Implement/Update `recordCreationLatencyMetric`

The function should look something like this:

```go
func (r *SandboxClaimReconciler) recordCreationLatencyMetric(ctx context.Context, claim *extensionsv1alpha1.SandboxClaim, originalClaimStatus extensionsv1alpha1.SandboxClaimStatus, sandbox *v1alpha1.Sandbox) {
    // Record Prometheus Metric for SandboxClaim creation-to-ready latency
    wasReady := meta.IsStatusConditionTrue(originalClaimStatus.Conditions, string(v1alpha1.SandboxConditionReady))
    isReady := meta.IsStatusConditionTrue(claim.Status.Conditions, string(v1alpha1.SandboxConditionReady))
    if !wasReady && isReady {
        key := claim.Namespace + "/" + claim.Name
        if _, loaded := r.readyClaims.LoadOrStore(key, true); !loaded {
            latencySeconds := time.Since(claim.CreationTimestamp.Time).Seconds()
            asmetrics.SandboxClaimReadyLatency.WithLabelValues(claim.Namespace).Observe(latencySeconds)

            // CRITICAL: Record SandbClaimReadyMS in milliseconds to logs
            log := log.FromContext(ctx)
            log.Info("SandbClaimReadyMS", "namespace", claim.Namespace, "name", claim.Name, "latency_ms", time.Since(claim.CreationTimestamp.Time).Milliseconds())
        }
    }
}
```

**Key Requirement:** The log line MUST contain the string `"SandbClaimReadyMS"` and the `latency_ms` field. This is what the analysis scripts look for.

## 4. Call `recordCreationLatencyMetric`
Ensure this function is called at the end of the `Reconcile` loop, typically after successfully reconciling conditions.

```go
    // At the end of Reconcile
    r.recordCreationLatencyMetric(ctx, claim, originalClaim.Status, sandbox)
```

## 5. Verify
Run a small test and check the controller logs to ensure `SandbClaimReadyMS` lines are appearing.
