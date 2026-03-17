# Design Proposal: Dynamic Network Policy Reconciliation

## 1. Summary
Agent workloads execute arbitrary, untrusted code. To prevent malicious lateral movement or unauthorized exfiltration, this proposal introduces dynamic `NetworkPolicy` orchestration natively within the `SandboxClaim` controller. The controller will automatically generate, apply, and delete bounding network policies based on the `SandboxTemplate` specifications.

## 2. Motivation
Currently, network isolation is largely handled manually or through static manifests deployed out-of-band by administrators. If a developer forgets to apply the restrictive network policy to an agent's namespace, the agent could potentially access internal service IP ranges (like cloud metadata servers `169.254.169.254`, internal databases, or Kubernetes API endpoints), posing a massive security risk.

Automating the application of zero-trust network boundaries guarantees that the moment a `SandboxClaim` is fulfilled, the corresponding Pods are instantly locked down according to the rules pre-defined in the `SandboxTemplate`.

## 3. Goals & Non-Goals
### Goals
- Automatically generate a `networkingv1.NetworkPolicy` targeting the assigned Sandbox whenever a claim is active.
- Default to strict denial of all ingress and egress traffic except DNS (Port 53).
- Provide an explicit opt-out mechanism via the `SandboxTemplate` (`DisableNetworkPolicy: true`).
- Clean up stranded or malicious network policies if the template intends for an open network.

### Non-Goals
- Implementing complex, multi-tier custom network routing per individual Sandbox. The policy generated is a blanket deny-all override.
- Supporting network plugins that do not respect Kubernetes `NetworkPolicy` primitives.

## 4. Proposal / Architecture
The controller will introduce a new sequential step during the primary reconciliation loop of a `SandboxClaim`: `reconcileNetworkPolicy(ctx, claim)`.

### 4.1 Applying Default Policies
1. The controller inspects the `SandboxTemplate` associated with the claim.
2. If `DisableNetworkPolicy` is **false** (the default secure state):
   - Generates a `networkingv1.NetworkPolicy` resource.
   - Sets the `PodSelector` to target the specific `Sandbox` pods via their label hash.
   - Defines a `PolicyTypes` array containing both `Ingress` and `Egress`.
   - The `Egress` array allows UDP/TCP Port 53 (DNS) to `0.0.0.0/0`, but explicitly denies all other routes (both Ingress and Egress).
   - Issues a `client.Create` or updates an existing policy.

### 4.2 Handling Disabled Policies
If `DisableNetworkPolicy` is toggled **true**:
1. The controller queries the cluster for any existing `NetworkPolicy` bound to the Sandbox claim.
2. If found, it issues a `client.Delete` to forcibly remove the restrictions.

## 5. Alternatives Considered
- **Webhook Injection (MutatingAdmissionWebhook)**: Injecting sidecar proxies or modifying pods on creation to block networking via IP tables. *Rejected* as standard CNI-backed Kubernetes `NetworkPolicy` is far more integrated, native, and maintainable.
- **Namespace-level Default Deny**: Setting a default deny on the entire namespace. *Considered but insufficient*, as we might run mix-workloads or manager pods in the same namespace which require egress. Sandbox-specific selectors are safer.

## 6. Implementation Plan
1. Centralize the policy scaffolding logic in `controllers/network_policy.go`.
2. Integrate a call to this function directly after the Sandbox is adopted in `sandboxclaim_controller.go`.
3. Add full `networking.k8s.io/networkpolicies` RBAC permissions to the controller's ClusterRole.

## 7. Testing & Verification Plan
- **Verification of Logs**: Spin up a multi-claim load test and verify no `NetworkPolicy` creation errors are logged.
- **E2E Curl Test**: Launch a `SandboxClaim` without the override flag. Exec into the assigned Sandbox pod and attempt to `curl 8.8.8.8` (should timeout). Attempt to `curl example.com` (DNS should resolve, but connection should timeout).

## 8. Affected Files
- `extensions/controllers/sandboxclaim_controller.go`
