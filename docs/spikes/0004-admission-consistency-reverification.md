# Spike 4: Admission-side consistency re-verification

* **Target tier:** tiers 3 and 4
* **Enforcement point:** the Kyverno admission webhook
* **Size:** M
* **Controls:** A.8.9 (configuration management), A.8.32 (change management), A.8.25 (secure development lifecycle)

## Question

Which consistency checks must run at admission for CI-attested inputs to genuinely bind the object that gets
deployed?

## Why the gap exists

This spike is the direct consequence of
[ADR-0001](../adr/0001-gate-attests-inputs-admission-verifies-consistency.md). CI attests the inputs, but
`ArtifactGenerator` composes the chart and the values into an `ExternalArtifact` in-cluster, so the object
that reaches the API server was assembled after every signature was issued. An attestation on the inputs
constrains the deployed object only through whatever checks admission actually performs.

Stated as a rule: **any input fact that admission does not re-verify is a fact the gate does not enforce.**
The signature's cryptographic strength is irrelevant to facts nobody checks.

The repository already demonstrates the shape at a small scale.
`clusterpolicy-disallow-manual-image-revision.yaml` fetches the image's OCI config at admission and requires
the `example.com/image-revision` annotation to equal
`org.opencontainers.image.revision` from the registry, so the annotation cannot be forged. That is exactly
this pattern, applied to exactly one field. The spike generalises it.

## Investigation approach

**Enumerate the drift surface.** For each fact the gate relies on, establish whether admission can observe
it and re-verify it. Start with the facts already known to matter: the running image reference, the approval
predicate covering that image, the values payload digest the composition consumed, and the identity of the
publishing actor. The values payload is the hard one — the composed `ExternalArtifact` is not visible to a
`Deployment`-scoped policy, so establish what, if anything, ties the admitted workload back to a specific
attested values digest. If nothing does, say so: that is a finding, and it bounds every other spike's claims.

**Close the container blind spot.** All three tier-4 `ClusterPolicy` objects and the chart-packaged `Policy`
inspect only `spec.template.spec.containers[0]`. A second container, an `initContainers` entry, or an
ephemeral container is entirely unchecked, which makes the gate trivially evadable by adding a container
rather than replacing one. Any consistency check written here must iterate all container collections. The
tier-4 README already flags this for the existing policies; it is load-bearing for the gate.

**Decide the fail-closed semantics, and mean it.** These policies make live outbound calls during admission
— to the OCI registry via `imageRegistry` context, and at tiers 3 and 4 to SpiceDB. Only
`clusterpolicy-verify-image-nginx-ancestor.yaml` sets `webhookTimeoutSeconds`, and `kyverno.tf` passes no
Helm values at all, so replica counts and webhook failure policy are whatever the chart defaults to.
Characterise what actually happens when Kyverno is unavailable, SpiceDB is unreachable, or the registry is
slow. For a control asserted to fail closed, the answer is either a cluster-wide deploy outage or a silent
fail-open, and which one it is should be a decision rather than a discovery.

**Consider the point-in-time limitation.** Every policy sets `background: false`, so nothing re-evaluates
workloads that were already admitted. A gate introduced today never examines what is already running, and
post-admission drift is never caught. Determine whether the approval gate needs background scanning to be
credible as a continuous control, given that A.8.9 expects configurations to be monitored rather than merely
set.

## Done when

You have a written enumeration of the facts the gate depends on, each marked as re-verified at admission or
explicitly not, a policy demonstration that rejects a `Deployment` whose image does not match its attested
approval predicate across *all* containers, and a decided position on webhook failure behaviour and
background scanning.
