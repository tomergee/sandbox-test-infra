# Design Proposal: Conflict-Free Status Updates

## 1. Summary
Across the core controllers (`sandbox_controller`, `sandboxclaim_controller`, `sandboxwarmpool_controller`), status updates are currently performed via direct `Status().Update()` calls. This proposal mandates replacing all such calls with JSON Merge Patching (`Status().Patch()`) to eradicate fatal state collision errors during high-throughput scaling scenarios.

## 2. Motivation
During large-scale multiburst testing (e.g., orchestrating 50 claims against 50 warm pool instances simultaneously), multiple worker threads and controllers race to observe and modify the same underlying Custom Resources. 

When establishing state using a standard `Update()`, the client sends the entire object payload along with a strict `resourceVersion`. If the object was modified by another thread literally milliseconds prior, the API server hard-rejects the update, returning the fatal error: `object has been modified; please apply your changes to the latest version and try again`.

This forces the reconciliation loop to crash, back-off, and retry, destroying performance scaling and flooding the apiserver with retry loops. Moving to a declarative patch strategy solves this cleanly.

## 3. Goals & Non-Goals
### Goals
- Refactor all `Status().Update(ctx, obj)` calls to `Status().Patch(...)` across all 3 major controllers.
- Eradicate "Object has been modified" collision errors from the controller logs during routine scale-out bursts.
- Ensure state updates arrive atomically without requiring brute-force retry loops.

### Non-Goals
- Altering the fundamental state machine of the Sandbox or Claims themselves.
- Optimizing `Update` calls for the `Spec` field, as `Spec` mutations are owned strictly by the user or upstream automation (though the paradigm applies similarly if needed).

## 4. Proposal / Architecture
We propose weaving a strict "Fetch, Copy, Patch" algorithm anywhere a state change needs to be published to a Custom Resource.

### The Patch Algorithm
1. **Fetch Latest Representation**: Directly before a status calculation occurs, fetch the absolutely latest representation of the object directly from the API server cache.
2. **Copy the Base**: Establish a deep-copy or tracking reference of this original object (e.g., `original := obj.DeepCopy()`).
3. **Mutate the Base**: Adjust the `.Status` fields on the `obj` variable.
4. **Generate the Patch**: Create a formal JSON merge patch diffing the two objects via controller-runtime libraries: `patch := client.MergeFrom(original)`.
5. **Issue Atomic Patch**: Fire the patch dynamically to the API server: `r.Status().Patch(ctx, obj, patch)`. 

Because a patch only delivers the *delta* of the specific fields changed, the API server can cleanly weave these changes in, even if the `resourceVersion` has advanced due to other completely unrelated fields (or labels) shifting in parallel.

## 5. Alternatives Considered
- **Exponential Backoff on Updates**: Keeping `Update()` but writing wrappers to silently catch the modification error, wait 10ms-1s, refetch, and update again. *Rejected* because this artificially stalls worker threads during critical scaling paths and increases apimachinery load.
- **Server-Side Apply (SSA)**: The pinnacle of declarative patching. *Considered but Deferred* because it is significantly more complex to engineer and requires strictly defining field managers for every operation. Simple JSON merge patching achieves 99% of the collision-resistance with standard code.

## 6. Implementation Plan
1. Audit `sandboxclaim_controller.go`, `sandbox_controller.go`, and `sandboxwarmpool_controller.go` for all `.Update(ctx` occurrences.
2. Replace these with the standard `client.MergeFrom` logic template.
3. Validate error trapping strategies ensure patches don't silently fail if the object doesn't actually exist on the server.

## 7. Testing & Verification Plan
- **Verification of Logs**: Spin up a heavy test suite (e.g., 200 node scale) and physically `grep` the controller pod logs for the string `object has been modified`. The metric should drop to near zero.
- **Metrics Aggregation**: Ensure the `reconciliation_errors_total` metric exposed by controller-runtime experiences a proportional drop under load.
