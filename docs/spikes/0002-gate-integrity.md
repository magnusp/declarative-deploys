# Spike 2: Gate integrity

* **Target tier:** tier 2 onward
* **Enforcement point:** repository ownership rules, OIDC trust policy, registry permissions, and cluster
  RBAC
* **Size:** M
* **Controls:**
  * A.5.3 — segregation of duties
  * A.8.2 — privileged access rights
  * A.8.4 — access to source code
  * A.8.9 — configuration management
  * A.8.24 — use of cryptography

## Question

What configuration prevents the person introducing a change from also changing the gate that judges it?

## Why the gap exists

Four-eyes review takes its independence from a person: the approver is someone other than the author. An
automated gate has no equivalent property. It stays independent only while the change author cannot alter
it, and "alter it" covers more surfaces than it first appears to.

A gate that the gated party can weaken is not a weaker control. It is not a control.

## Investigation approach

Work through each surface and establish the configuration that closes it. The weakest surface determines
the gate's actual strength.

### The gate definition

The rules live on platform-owned paths: `clusters/kind/` for `ClusterPolicy` objects,
`charts/archetype-backend/` for the chart-packaged `Policy`, and `.github/workflows/` for the
publication-side checks. Establish path-scoped review requirements so that an application team's pull
request cannot modify them, and confirm that no one can self-approve such a change.

At tier 4 the chart packages a Kyverno `Policy` alongside the workload it governs, which makes the chart a
gate surface. Check whether application-supplied values can influence how that policy renders. They cannot
today, because `archetype-backend.name` resolves from `.Release.Name`, which the platform-owned
`HelmRelease` sets. Assert that property deliberately rather than relying on it.

### The signing identity

This surface carries the most weight, and the mechanism is confirmed on both enforcement paths. An
attestation means something only if the gated party cannot mint an equivalent one. Keyless Sigstore signing
records the issuing workflow in the Fulcio certificate, and both consumers can pin on it:

* **Kyverno** supports a `keyless` attestor entry with `issuer` and `subject`, or `subjectRegExp`, inside a
  `verifyImages` `attestations` block.
* **Flux** supports `matchOIDCIdentity`, a list of `issuer` and `subject` pairs evaluated as Go regular
  expressions against the certificate identity.

The question is therefore not whether to pin but how tightly, and what happens when you get it wrong.
Anchor both patterns to a full workflow reference rather than a repository prefix. A subject expression such
as `^https://github.com/magnusp/declarative-deploys.*$` matches any workflow in the repository, including
one an application team adds, which removes the control while appearing to implement it. Then confirm the
negative case: an application team copies the gate workflow to a path they own, and verification rejects
the attestation it produces.

### Registry write access

Anyone who can push to `ghcr.io/magnusp/apps/*` can publish an image with arbitrary OCI labels and an
arbitrary values artifact, which bypasses CI. At tier 2 this defeats the gate, because no admission
controller exists to catch it. At tiers 3 and 4 it is contained only as far as admission re-verifies, which
[spike 4](0004-admission-consistency-reverification.md) covers. Establish who holds write access to which
registry paths.

### Cluster-side tampering

Enumerate what an application team with elevated namespace access can do to the gate from inside the
cluster. They might create a Kyverno `PolicyException` that exempts their workload, patch a `ClusterPolicy`
to change `failureAction` from `Enforce` to `Audit`, or edit the `HelmRelease`. Flux reconciles these from
git and reverts drift, but reversion is eventual, and any deploy admitted during that window stays
admitted. Determine whether the gate needs `PolicyException` disabled outright or governed by its own
policy.

### Break-glass

Decide how an operator bypasses the gate in an emergency, and how the system records that bypass. An
undocumented bypass path becomes an undocumented routine.

## Done when

You can name the specific configuration that closes each of the five surfaces in this document, together
with the demonstration that proves it. The most important demonstration: verification rejects an approval
attestation minted by a workflow the application team controls.

## Notes

Two showcase artifacts are relevant here, and neither is the design gap:

* **The repository contains no `CODEOWNERS` file**, so the platform and application ownership split that
  the tiers demonstrate is currently conventional rather than enforced. That suits a demonstration, and it
  is also the configuration that would convert the split into an automated control. Record it here.
* **The SpiceDB preshared key is committed in plaintext.** `spicedb-cluster.yaml` carries
  `stringData.preshared_key: "showcase-authz-key"`, and `clusterpolicy-spicedb-authz.yaml` hardcodes the
  matching `Bearer showcase-authz-key`. This is a demo credential. The design question it conceals belongs
  to this spike: how does an enforcement point authenticate to the service it consults without a static
  token in a git-synced manifest, given that the credential grants write access to the authorization data
  itself?
