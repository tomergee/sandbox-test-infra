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
Locate the `recordCreationLatencyMetric` method. It should calculate the exact time the status condition changed to `Ready` using `LastTransitionTime` instead of `time.Since()`, which avoids including the controller's queue waiting time:

```go
func (r *SandboxClaimReconciler) recordCreationLatencyMetric(ctx context.Context, claim *extensionsv1alpha1.SandboxClaim, originalClaimStatus extensionsv1alpha1.SandboxClaimStatus, sandbox *v1alpha1.Sandbox) {
	newStatus := &claim.Status
	newReady := meta.FindStatusCondition(newStatus.Conditions, string(v1alpha1.SandboxConditionReady))
	if newReady == nil || newReady.Status != metav1.ConditionTrue {
		return
	}

	// Do not record creation metric if we have already seen the ready state.
	oldReady := meta.FindStatusCondition(originalClaimStatus.Conditions, string(v1alpha1.SandboxConditionReady))
	if oldReady != nil && oldReady.Status == metav1.ConditionTrue {
		return
	}

	// Record Prometheus Metric for SandboxClaim creation-to-ready latency
	key := claim.Namespace + "/" + claim.Name
	if _, loaded := r.readyClaims.LoadOrStore(key, true); !loaded {
		readyTime := newReady.LastTransitionTime.Time
		latency := readyTime.Sub(claim.CreationTimestamp.Time)
		
		latencySeconds := latency.Seconds()
		asmetrics.SandboxClaimReadyLatency.WithLabelValues(claim.Namespace).Observe(latencySeconds)

		// ADD THIS BLOCK: Record SandbClaimReadyMS log
		log := log.FromContext(ctx)
		log.Info("SandbClaimReadyMS", "namespace", claim.Namespace, "name", claim.Name, "latency_ms", latency.Milliseconds())
	}
    // ... remainder of method
}
```

## 4. Extracting Results
You can then extract the metrics from the controller pod logs using standard grepping or Python scripts passing over the pod's logs:
```bash
kubectl logs -n agent-sandbox-system deployment/agent-sandbox-controller | grep SandbClaimReadyMS
```
