# Spikes: automated change approval for tiers 2 through 4

These are time-boxed investigations, not implementations. They exist to answer one question:
**when the pull request disappears, what replaces the approval it carried?**

## Why these spikes exist

Tiers 0 and 1 satisfy ISO/IEC 27001 change-management expectations almost incidentally. The application
team commits to git, so every change travels through a pull request, and somebody other than the author
approves it before it merges. Four-eyes review is the control, and the git history is the evidence. Nobody
had to design that — it fell out of the delivery mechanism.

Tier 2 removes the delivery mechanism. The application team stops committing to `clusters/kind/` and starts
publishing OCI artifacts instead: an image tagged with a commit SHA, and a values artifact on a mutable
`latest` tag. Publishing *is* the deploy. That is the point of the tier, and it is also the moment the
approval control silently vanishes — there is no pull request against the thing that deploys, so there is
nobody to approve it.

Tiers 3 and 4 add real governance on top: SpiceDB ReBAC authorization at admission, image-provenance
policies, and a Policy Reporter audit trail. None of them restore the missing control. Tier 4's own README
is candid about this — deploy-time authorization answers *was this actor allowed?*, and build provenance
answers *where did this artifact come from?*, but neither answers *was this change examined before it
shipped?*

The spikes below investigate automated pre-exposure gates that answer that third question without a human
in the loop.

## Two lifecycles, one gap

Changes travel two separate paths in tiers 2 through 4, and only one of them lost its control:

* **Code and configuration lifecycle** — application code, `Dockerfile`, the platform chart, cluster
  manifests, and the checked-in `values.yaml`. Still gated behind a pull request with multiple reviewers.
  Not in question here.
* **Deploy lifecycle** — publishing the values artifact that rolls a new image into the cluster. One change
  classification, no human approval, no gate. **This is what the spikes target.**

The separation is leakier than it looks. `.github/workflows/publish-app-values.yaml` rewrites `image.tag`
in the working copy with `yq -i` and never commits the result, so the values artifact that deploys is not
the values file anyone reviewed. The repository's `apps-source/values.yaml` says `tag: "latest"`; what
ships is whatever SHA someone typed into a `workflow_dispatch` input. The deploy lifecycle's payload is
unreviewed by construction, not by oversight.

## The progression

Where a gate can be enforced depends on what each tier actually runs, which gives the spike set its spine.

* **Tier 2 — publication gates only.** Tier 2 bootstraps Flux and nothing else; there is no admission
  controller, because `kyverno.tf` first appears in tier 3. The only available enforcement point is the CI
  workflow, refusing to publish an artifact that fails its checks. That closes the gap for changes that go
  through CI and cannot close it for any that do not — anyone able to push to the GHCR path bypasses CI
  entirely, and tier 2's `OCIRepository` has no `verify:` block, so Flux pulls and deploys the result
  without objection. **Tier 2's gap is only partially closable within tier 2.** Worth stating plainly.
* **Tier 3 — admission gates become possible.** Kyverno arrives. The cluster can now stop trusting the
  publication path and instead demand a valid attestation at admission time, which is what makes the
  approach in [ADR-0001](../adr/0001-gate-attests-inputs-admission-verifies-consistency.md) enforceable
  rather than advisory.
* **Tier 4 — the gate generalises and leaves evidence.** Label-scoped governance
  (`governance.platform.io/managed`) makes one gate apply across any number of application workspaces, and
  Policy Reporter gives the gate's decisions somewhere durable to land.

## Architectural assumption

All five spikes assume the approach recorded in
[ADR-0001](../adr/0001-gate-attests-inputs-admission-verifies-consistency.md): **CI attests the inputs, and
admission re-verifies consistency.**

This matters because `ArtifactGenerator` composes the platform chart with the application values into an
`ExternalArtifact` in-cluster, at reconcile time. The artifact that actually deploys never exists in CI, so
no CI-issued signature can cover it directly. Rendering the composition in CI instead would regress tier 2's
premise, and signing the `ExternalArtifact` in-cluster would put the signer inside the blast radius it is
meant to protect. Attesting inputs and re-verifying at admission preserves runtime composition while keeping
the signing identity outside the cluster.

The cost of that choice is inherited by every spike here: **the gate is only as strong as the completeness
of the admission-time consistency checks.** Spike 4 exists to establish how complete those checks must be.

## Known-viable work that precedes the spikes

Two items below are **not** spikes, because they are no longer investigations — the mechanisms are
confirmed, and only the wiring is missing. They are listed here because every spike is easier once they
exist, and because both are worth doing on their own merits whether or not the approval gates are ever
scheduled.

Both workflows already produce signed SLSA provenance with `push-to-registry: true`, and **nothing
consumes it**: neither `OCIRepository` carries a `verify:` block, and no policy uses `verifyImages`. The
evidence is signed and discarded. Meanwhile `clusterpolicy-spicedb-authz.yaml` derives the acting identity
from `imageData.configData.config.Labels` — unsigned OCI metadata that anyone able to push to the registry
path can set arbitrarily. The trustworthy copy sits unconsumed beside the forgeable one.

1. **Verify the image provenance at admission** *(tiers 3 and 4)*. Add a `verifyImages` rule with a keyless
   attestor pinned to `build-app-image.yaml`'s OIDC issuer and subject. An image the platform's own
   workflow did not build then fails admission, which closes the arbitrary-image substitution path and
   makes `image.repository` being unconstrained in `values.schema.json` far less consequential. It also
   offers a principled replacement for `clusterpolicy-verify-image-nginx-ancestor.yaml`, whose hardcoded
   layer-digest allowlist carries no cryptographic guarantee and goes stale whenever the upstream
   `nginx:1.27` base image is rebuilt.
2. **Sign the artifacts and verify them at the source** *(tier 2 onward)*. Add a `cosign sign` step to both
   workflows and a `verify:` block with `matchOIDCIdentity` to both `OCIRepository` objects. The extra
   signing step is necessary: `actions/attest-build-provenance` produces an *attestation*, and Flux's
   `verify` checks *plain signatures*, so what is pushed today would not satisfy it. This is the only
   in-cluster verification tier 2 can host.

Be clear about what these buy. They establish **provenance of origin** — the artifact came from a known
workflow in a known repository. They say nothing about whether the change was examined, so they neither
restore the approval control nor substitute for any spike below. They also make admission and
reconciliation newly dependent on registry reachability and Sigstore verification, which sharpens the
availability question in [spike 4](0004-admission-consistency-reverification.md) rather than answering it.

## The spikes

1. **[Provenance-chained four-eyes](0001-provenance-chained-four-eyes.md)** *(tier 2 publication, tier 3/4
   admission — size M)* — prove both deploy inputs descend from commits that passed multi-reviewer pull
   requests, and carry that proof where the cluster can check it. The primary option: it reconstructs the
   tier 0/1 control rather than substituting a different one.
2. **[Gate integrity](0002-gate-integrity.md)** *(tier 2 onward — size M)* — stop the change author from
   minting their own approval or weakening the rule that judges them. Without this, spikes 1, 3, and 4 are
   all forgeable.
3. **[Publication-side policy gate](0003-publication-side-policy-gate.md)** *(tier 2 — size S)* —
   policy-as-code on the deploy payload before `flux push`, plus hardening
   `charts/archetype-backend/values.schema.json`, which currently permits an arbitrary registry and an
   arbitrary floating tag.
4. **[Admission-side consistency re-verification](0004-admission-consistency-reverification.md)** *(tier 3/4
   — size M)* — enumerate the checks that must run at admission for attested inputs to genuinely bind the
   admitted object. Any input fact admission does not re-verify is a fact the gate does not enforce.
5. **[Evidence that the gate ran](0005-gate-decision-evidence.md)** *(tier 4 — size S)* — whether denials
   land durably in `PolicyReport` data, and what record demonstrates the approval control operated on every
   deploy rather than merely existing.

Spikes 1 and 2 are the load-bearing pair. Spike 2 should not trail far behind spike 1, since an
unforgeable-approval design that can be forged is not a partial result — it is the wrong result.

## Deliberately out of scope

Tier 2's README raises two further mitigations. Both are excluded here by decision, not oversight, because
the mandate for these spikes is **pre-exposure gating**:

* **Progressive delivery with automatic rollback.** Bounds blast radius *after* exposure rather than
  preventing it, so it is a compensating control, not a gate. Revisit only if a change classification scheme
  is introduced that makes a rollback-only path defensible for some class of change.
* **Sampled or after-the-fact human review.** Reintroduces the human intervention these spikes exist to
  remove.

## Showcase artifacts, not spikes

This repository is a demonstration, so some shortcomings are deliberate simplifications rather than gaps in
the tier design. They are recorded where relevant inside the spikes, but they are not spike subjects:

* **No `CODEOWNERS`.** The platform/application ownership split is conceptual here. In a real adoption,
  path-scoped ownership enforcement is exactly what converts that split from a convention into an automated
  control — see [spike 2](0002-gate-integrity.md).
* **`datastoreEngine: memory` for SpiceDB, and Policy Reporter's SQLite on a kind `local-path` volume.**
  Storage choices appropriate to an ephemeral kind cluster. The design question they obscure — what evidence
  the gate must emit to be auditable at all — is [spike 5](0005-gate-decision-evidence.md).
* **The plaintext `showcase-authz-key` preshared key.** A demo credential. The design question behind it —
  how an enforcement point authenticates without a human handling a static token — surfaces in
  [spike 2](0002-gate-integrity.md).
