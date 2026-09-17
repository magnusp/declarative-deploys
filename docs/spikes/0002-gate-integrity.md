# Spike 2: Gate integrity

* **Target tier:** tier 2 onward
* **Enforcement point:** repository ownership rules, OIDC trust policy, registry permissions, and cluster
  RBAC
* **Size:** M
* **Controls:**
  * A.5.3 — segregation of duties
  * A.8.2 — privileged access rights
  * A.8.4 — access to source code
  * A.8.18 — use of privileged utility programs
  * A.8.24 — use of cryptography

## Question

What configuration prevents the person introducing a change from also changing the gate that judges it?

## Why the gap exists

Four-eyes review derives its independence from a person: the approver is someone other than the author, and
that is the whole mechanism. An automated gate has no such natural independence. It is independent only for
as long as the change author cannot alter it — and "altering it" has more surfaces than it first appears.

A gate that the gated party can weaken is not a weaker control. It is not a control.

## Investigation approach

Work through each surface and establish what configuration closes it. The gate's own trust story is only as
strong as the weakest one.

**The gate definition.** The rules live on platform-owned paths: `clusters/kind/` for `ClusterPolicy`
objects, `charts/archetype-backend/` for the chart-packaged `Policy`, and `.github/workflows/` for the
publication-side checks. Establish path-scoped review requirements so an application team's pull request
cannot touch them, and confirm the requirement cannot be self-approved. Note that at tier 4 the chart
packages a Kyverno `Policy` alongside the workload it governs, which makes the chart itself a gate surface —
worth checking whether application-supplied values can influence how that policy renders. They currently
cannot, because `archetype-backend.name` resolves from `.Release.Name`, which the platform-owned
`HelmRelease` sets, but that is a property worth asserting deliberately rather than inheriting by luck.

**The signing identity.** This is the half with the most leverage, and the mechanism is confirmed to exist
on both enforcement paths. An attestation is only meaningful if the gated party cannot mint an equivalent
one. Keyless Sigstore signing records the issuing workflow in the Fulcio certificate, and both consumers can
pin on it:

* **Kyverno** supports a `keyless` attestor entry with `issuer` and `subject` (or `subjectRegExp`) inside a
  `verifyImages` `attestations` block.
* **Flux** supports `matchOIDCIdentity`, a list of `issuer`/`subject` pairs evaluated as Go regular
  expressions against the certificate identity.

The investigation is therefore not *whether* to pin but *how tightly*, and the failure modes of getting it
wrong. Anchor both patterns to a full workflow reference rather than a repository prefix — a subject regex
such as `^https://github.com/magnusp/declarative-deploys.*$` matches **any** workflow in the repository,
including one an application team adds, which defeats the entire control while appearing to implement it.
Then confirm the negative case directly: an application team copies the gate workflow to a path they own,
and verification must reject the attestation it produces.

**Registry write access.** If anyone can push to `ghcr.io/magnusp/apps/*`, they can publish an image with
arbitrary OCI labels and an arbitrary values artifact, bypassing CI entirely. At tier 2 this is fatal, since
there is no admission controller to catch it; at tiers 3 and 4 it is contained only to the extent that
admission actually re-verifies (spike 4). Scope who holds write access to which registry paths.

**Cluster-side tampering.** Enumerate what an application team with elevated namespace access could do to
the gate from inside: create a Kyverno `PolicyException` exempting their workload, patch a `ClusterPolicy`
to flip `failureAction` from `Enforce` to `Audit`, or edit the `HelmRelease`. Flux reconciles these from git
and will revert drift, but reversion is eventual, and a deploy admitted during the window is admitted
permanently. Establish whether the gate needs `PolicyException` disabled outright, or governed by its own
policy.

**Break-glass.** Decide deliberately how the gate is bypassed in an emergency, and how that bypass is
recorded. An undocumented bypass path becomes an undocumented routine.

## Done when

You can name, for each of the five surfaces above, the specific configuration that closes it and the
demonstration that proves it — most importantly a demonstration that an approval attestation minted by a
workflow the application team controls is rejected.

## Notes

Two showcase artifacts are relevant here, and neither should be mistaken for the design gap:

* **There is no `CODEOWNERS` file anywhere in the repository**, so the platform/application ownership split
  that the tiers exist to demonstrate is currently conceptual. That is appropriate for a demonstration, and
  it is also precisely the configuration that would convert the split into an automated control. This spike
  is where that gets written down.
* **The SpiceDB preshared key is committed in plaintext** — `spicedb-cluster.yaml` carries
  `stringData.preshared_key: "showcase-authz-key"` and `clusterpolicy-spicedb-authz.yaml` hardcodes the
  matching `Bearer showcase-authz-key`. A demo credential, obviously. The design question it obscures is
  real and belongs to this spike: how does an enforcement point authenticate to the service it consults
  without a static token sitting in a git-synced manifest, given that the credential grants write access to
  the authorization data itself?
