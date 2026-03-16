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
The `SandbClaimReadyMS` metric needs to measure the exact milliseconds between when the claim was requested (`CreationTimestamp`) and when it was definitively verified as ready by the API server. This is achieved using `time.Since(claim.CreationTimestamp.Time)`.

First, locate the `Reconcile` method and ensure `recordCreationLatencyMetric` is called **AFTER** `updateStatus` so that we only log the latency when the status is successfully persisted to the cluster:

```go
	if updateErr := r.updateStatus(ctx, originalClaimStatus, claim); updateErr != nil {
		return ctrl.Result{}, errors.Join(reconcileErr, updateErr)
	}

	// This is placed after updateStatus so that the measurement includes the successful persist to the API server
	r.recordCreationLatencyMetric(ctx, claim, *originalClaimStatus, sandbox)
```

Then, in the `recordCreationLatencyMetric` method itself, add the JSON-formatted logging inside the block that checks the `readyClaims` map first:

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
		latencySeconds := time.Since(claim.CreationTimestamp.Time).Seconds()
		asmetrics.SandboxClaimReadyLatency.WithLabelValues(claim.Namespace).Observe(latencySeconds)

		// ADD THIS BLOCK: Record SandbClaimReadyMS log
		log := log.FromContext(ctx)
		log.Info("SandbClaimReadyMS", "namespace", claim.Namespace, "name", claim.Name, "latency_ms", time.Since(claim.CreationTimestamp.Time).Milliseconds())
	}
    // ... remainder of method
}
```

## 4. Extracting Results
You can then extract the metrics from the controller pod logs using standard grepping or Python scripts passing over the pod's logs:
```bash
kubectl logs -n agent-sandbox-system deployment/agent-sandbox-controller | grep SandbClaimReadyMS
```
