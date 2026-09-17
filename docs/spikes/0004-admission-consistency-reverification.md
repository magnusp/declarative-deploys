# Spike 4: Admission-side consistency re-verification

* **Target tier:** tiers 3 and 4
* **Enforcement point:** the Kyverno admission webhook
* **Size:** M
* **Controls:**
  * A.8.9 — configuration management
  * A.8.25 — secure development lifecycle
  * A.8.32 — change management

## Question

Which consistency checks must run at admission for CI-attested inputs to bind the object that deploys?

## Why the gap exists

This spike follows directly from the consequence that
[ADR-0001](../adr/0001-gate-attests-inputs-admission-verifies-consistency.md) records. CI attests the
inputs, but `ArtifactGenerator` composes the chart and the values into an `ExternalArtifact` inside the
cluster. The object that reaches the API server is therefore assembled after every signature was issued. An
attestation on the inputs constrains the deployed object only through the checks that admission performs.

Stated as a rule: **any input fact that admission does not re-verify is a fact the gate does not enforce.**
The cryptographic strength of a signature is irrelevant to facts that nothing checks.

The repository already demonstrates the pattern at small scale.
`clusterpolicy-disallow-manual-image-revision.yaml` fetches the image's OCI configuration at admission and
requires the `example.com/image-revision` annotation to equal `org.opencontainers.image.revision` from the
registry, so nothing can forge the annotation. This spike generalizes that approach.

## Investigation approach

### Enumerate the drift surface

For each fact the gate relies on, establish whether admission can observe it and re-verify it.

The mechanism for moving verified facts into policy logic is confirmed. Kyverno adds a successfully
verified attestation to the policy context under the name given in the `attestations` block, which makes
its predicate fields available to later rules and to subsequent `apiCall` contexts. That is how an attested
fact reaches a consistency check. It is also how `clusterpolicy-spicedb-authz.yaml` should obtain its
subject identity, instead of reading the unsigned `dev.authz.app.deployer` OCI label it reads today.

Start with the facts already known to matter: the running image reference, the approval predicate covering
that image, the values payload digest the composition consumed, and the identity of the publishing actor.
The values payload is the difficult one, because a `Deployment`-scoped policy cannot see the composed
`ExternalArtifact`. Establish what, if anything, ties the admitted workload back to a specific attested
values digest. If nothing does, record that. It is a finding, and it bounds the claims every other spike
can make.

### Close the container blind spot

All three tier-4 `ClusterPolicy` objects and the chart-packaged `Policy` inspect only
`spec.template.spec.containers[0]`. Nothing checks a second container, an `initContainers` entry, or an
ephemeral container, so adding a container rather than replacing one evades the gate. Every consistency
check written here must iterate all container collections. The tier 4 README flags this for the existing
policies; for the gate it is essential.

### Decide the fail-closed semantics

These policies make live outbound calls during admission, to the OCI registry through `imageRegistry`
context and, at tiers 3 and 4, to SpiceDB. Only `clusterpolicy-verify-image-nginx-ancestor.yaml` sets
`webhookTimeoutSeconds`, and `kyverno.tf` passes no Helm values, so the chart defaults determine replica
counts and webhook failure policy.

Establish what happens when Kyverno is unavailable, when SpiceDB is unreachable, and when the registry
responds slowly. For a control described as fail-closed, the outcome is either a cluster-wide deploy outage
or a silent fail-open. Make that a decision rather than a discovery.

### Consider the point-in-time limitation

Every policy sets `background: false`, so nothing re-evaluates workloads that admission already accepted. A
gate introduced today never examines what already runs, and nothing detects post-admission drift. Determine
whether the approval gate needs background scanning to work as a continuous control, given that A.8.9
expects configurations to be monitored rather than only set.

## Done when

You have a written enumeration of the facts the gate depends on, each marked as re-verified at admission or
explicitly not. You have a policy demonstration that rejects a `Deployment` whose image does not match its
attested approval predicate, across all containers. You have a decided position on webhook failure behavior
and on background scanning.
