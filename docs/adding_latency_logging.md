# Adding `SandbClaimReadyMS` Latency Logging

When working on a new branch of the agent-sandbox repository, the controller might be missing the `SandbClaimReadyMS` metric used for latency benchmarking. Here is how to add it to `sandboxclaim_controller.go`:

## 1. Add `readyClaims` Map to the Reconciler
Ensure the `SandboxClaimReconciler` struct has a `sync.Map` to prevent duplicate logging of the same claim. Add it if missing:

```go
import "sync"

type SandboxClaimReconciler struct {
    // ... existing fields ...
    readyClaims sync.Map
}
```

## 2. Clear Tracked Claims on Deletion
In the `Reconcile` function, when a claim is not found (deleted), remove it from the map to prevent memory leaks over time during large tests.

```go
func (r *SandboxClaimReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // ... setup code ...
    if err := r.Get(ctx, req.NamespacedName, claim); err != nil {
        if k8errors.IsNotFound(err) {
            // ADD THIS: Clear from tracking map
            key := req.Namespace + "/" + req.Name
            r.readyClaims.Delete(key)
            return ctrl.Result{}, nil
        }
        return ctrl.Result{}, fmt.Errorf("...")
    }
    // ...
```

## 3. Add the Logging Statement
Locate the `recordCreationLatencyMetric` method. Insert the JSON-formatted logging inside the block that detects the `!wasReady` to `isReady` transition, checking the `readyClaims` map first:

```go
func (r *SandboxClaimReconciler) recordCreationLatencyMetric(ctx context.Context, claim *extensionsv1alpha1.SandboxClaim, originalClaimStatus extensionsv1alpha1.SandboxClaimStatus, sandbox *v1alpha1.Sandbox) {
    wasReady := meta.IsStatusConditionTrue(originalClaimStatus.Conditions, string(v1alpha1.SandboxConditionReady))
    isReady := meta.IsStatusConditionTrue(claim.Status.Conditions, string(v1alpha1.SandboxConditionReady))
    
    if !wasReady && isReady {
        key := claim.Namespace + "/" + claim.Name
        if _, loaded := r.readyClaims.LoadOrStore(key, true); !loaded {
            latencySeconds := time.Since(claim.CreationTimestamp.Time).Seconds()
            asmetrics.SandboxClaimReadyLatency.WithLabelValues(claim.Namespace).Observe(latencySeconds)

            // ADD THIS BLOCK: Record SandbClaimReadyMS log
            log := log.FromContext(ctx)
            log.Info("SandbClaimReadyMS", 
                "namespace", claim.Namespace, 
                "name", claim.Name, 
                "latency_ms", time.Since(claim.CreationTimestamp.Time).Milliseconds(),
            )
        }
    }
    // ... remainder of method
}
```

## 4. Extracting Results
You can then extract the metrics from the controller pod logs using standard grepping or Python scripts passing over the pod's logs:
```bash
kubectl logs -n agent-sandbox-system deployment/agent-sandbox-controller | grep SandbClaimReadyMS
```
