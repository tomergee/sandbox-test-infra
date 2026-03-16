# Enhancement: Network Policy Reconciliation

## Background & Goal
Agent runs often involve extremely unprivileged workloads that require heavily restricted inbound and outbound networking rules to prevent malicious pivoting or data exfiltration. Previously, these network policies were applied entirely statically or manually through external scripts during the Sandbox lifecycle.

This enhancement directly weaves dynamic `NetworkPolicy` orchestration natively into the `SandboxClaim` Controller. By reading the `SandboxTemplate`, the controller can apply pre-defined egress/ingress blocking logic onto the namespace holding the assigned Sandbox.

## Implementation Plan
1. **Develop `reconcileNetworkPolicy` Functionality**:
   - Establish a helper function within `sandboxclaim_controller.go` capable of orchestrating networking boundaries for a specific pod identity.
   - Fetch the overarching `SandboxTemplate` assigned to the `SandboxClaim`.
2. **Apply Default Strict Egress (If Enabled)**:
   - If `DisableNetworkPolicy` is **not** set inside the `SandboxTemplate` spec, dynamically manifest a strict `networkingv1.NetworkPolicy` that targets the current Sandbox pods.
   - Issue a `CreateOrUpdate` logic loop against this policy to assure it acts as a permanent bounding box around the Sandbox even if modified manually.
3. **Clean Up Overlapping Policies (If Disabled)**:
   - If the `DisableNetworkPolicy` template flag is toggled on, the controller must actively delete existing `NetworkPolicy` resources overlapping with the adopted Sandbox to avoid orphaned rules permanently blocking the agent.

## Success Criteria
- The integration tests show a locked-down Sandbox is physically incapable of escaping to internal nodes or public endpoints unless whitelisted.
- Dynamically deleting the policy through the template accurately drops the restrictions within a single reconciliation tick.
