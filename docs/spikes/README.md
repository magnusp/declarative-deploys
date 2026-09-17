# Spikes: automated change approval for tiers 2 through 4

These documents are time-boxed investigations, not implementations. They answer one question: when the
pull request disappears, what replaces the approval it carried?

## Why these spikes exist

Tiers 0 and 1 meet ISO/IEC 27001 change-management expectations without designing for it. The application
team commits to git, so every change travels through a pull request, and someone other than the author
approves it before it merges. Four-eyes review is the control, and the git history is the evidence. The
delivery mechanism supplies both.

Tier 2 replaces the delivery mechanism. The application team stops committing to `clusters/kind/` and
publishes Open Container Initiative (OCI) artifacts instead: an image tagged with a commit SHA, and a
values artifact on a mutable `latest` tag. Publishing is the deploy. That is the purpose of the tier, and
it is also the point where the approval control disappears. No pull request exists against the thing that
deploys, so no one approves it.

Tiers 3 and 4 add governance on top: relationship-based access control (ReBAC) authorization at admission,
image-provenance policies, and a Policy Reporter audit trail. None of them restore the missing control. The
tier 4 README states this directly. Deploy-time authorization answers whether the actor was allowed.
Build-time provenance answers where the artifact came from. Neither answers whether anyone examined the
change before it shipped.

These spikes investigate automated pre-exposure gates that answer that third question without a human.

## Two lifecycles, one gap

Changes travel two separate paths in tiers 2 through 4, and only one of them lost its control:

* **Code and configuration lifecycle.** Application code, the `Dockerfile`, the platform chart, cluster
  manifests, and the checked-in `values.yaml`. Still gated behind a pull request with multiple reviewers.
  Not in question here.
* **Deploy lifecycle.** Publishing the values artifact that rolls a new image into the cluster. One change
  classification, no human approval, no gate. The spikes target this path.

The separation is weaker than it appears. `.github/workflows/publish-app-values.yaml` rewrites `image.tag`
in the working copy with `yq -i` and never commits the result. The values artifact that deploys is
therefore not the values file anyone reviewed. The repository's `apps-source/values.yaml` specifies
`tag: "latest"`, but what ships is whatever SHA an operator typed into a `workflow_dispatch` input. The
deploy lifecycle's payload is unreviewed by construction, not by oversight.

## The progression

What each tier runs determines where a gate can be enforced, which gives the spike set its structure.

* **Tier 2 supports publication gates only.** Tier 2 bootstraps Flux and nothing else, because `kyverno.tf`
  first appears in tier 3. The CI workflow is the only available enforcement point, and it enforces by
  refusing to publish an artifact that fails its checks. That closes the gap for changes that travel
  through CI and cannot close it for any that do not. Anyone able to push to the GitHub Container Registry
  (GHCR) path bypasses CI, and tier 2's `OCIRepository` carries no `verify:` block, so Flux pulls and
  deploys the result. **Tier 2 cannot host a bypass-resistant gate.**
* **Tier 3 makes admission gates possible.** Kyverno arrives. The cluster can stop trusting the publication
  path and instead require a valid attestation at admission. This is what turns the approach in
  [ADR-0001](../adr/0001-gate-attests-inputs-admission-verifies-consistency.md) from advisory into
  enforceable.
* **Tier 4 generalizes the gate and records its decisions.** Label-scoped governance
  (`governance.platform.io/managed`) applies one gate across any number of application workspaces, and
  Policy Reporter gives the gate's decisions durable storage.

## Architectural assumption

All five spikes assume the approach that
[ADR-0001](../adr/0001-gate-attests-inputs-admission-verifies-consistency.md) records: **CI attests the
inputs, and admission re-verifies consistency.**

This matters because `ArtifactGenerator` composes the platform chart with the application values into an
`ExternalArtifact` inside the cluster, at reconcile time. The artifact that deploys never exists in CI, so
no CI-issued signature covers it directly. Rendering the composition in CI regresses the tier 2 premise.
Signing the `ExternalArtifact` in the cluster places the signer inside the system it protects. Attesting
inputs and re-verifying at admission preserves runtime composition and keeps the signing identity outside
the cluster.

Every spike inherits the cost of that choice: **the completeness of the admission-time consistency checks
bounds the gate's strength.** [Spike 4](0004-admission-consistency-reverification.md) establishes how
complete those checks must be.

## Known-viable work that precedes the spikes

The two items in this section are not spikes, because they are no longer investigations. The mechanisms are
confirmed and only the wiring is missing. Every spike becomes easier once they exist, and both are worth
doing whether or not the approval gates are ever scheduled.

Both workflows already produce signed Supply-chain Levels for Software Artifacts (SLSA) provenance with
`push-to-registry: true`, and **nothing consumes it**. Neither `OCIRepository` carries a `verify:` block,
and no policy uses `verifyImages`. Meanwhile `clusterpolicy-spicedb-authz.yaml` derives the acting identity
from `imageData.configData.config.Labels`, which is unsigned OCI metadata that anyone able to push to the
registry path can set to any value. The verifiable identity exists and goes unread; the forgeable one
governs admission.

1. **Verify the image provenance at admission** *(tiers 3 and 4)*. Add a `verifyImages` rule with a keyless
   attestor pinned to the OpenID Connect (OIDC) issuer and subject of `build-app-image.yaml`. An image that
   the platform's own workflow did not build then fails admission. This closes the arbitrary-image
   substitution path and makes the unconstrained `image.repository` in `values.schema.json` far less
   consequential. It also offers a principled replacement for
   `clusterpolicy-verify-image-nginx-ancestor.yaml`, whose hardcoded layer-digest allowlist carries no
   cryptographic guarantee and becomes outdated whenever the upstream `nginx:1.27` base image is rebuilt.
2. **Sign the artifacts and verify them at the source** *(tier 2 onward)*. Add a `cosign sign` step to both
   workflows and a `verify:` block with `matchOIDCIdentity` to both `OCIRepository` objects. The extra
   signing step is necessary, because `actions/attest-build-provenance` produces an attestation and Flux's
   `verify` checks plain signatures. What the workflows push today does not satisfy it. This is the only
   in-cluster verification tier 2 can host.

Both items establish **provenance of origin**: the artifact came from a known workflow in a known
repository. Neither says anything about whether a check examined the change, so neither restores the
approval control nor substitutes for any spike. Both also make admission and reconciliation newly dependent
on registry reachability and Sigstore verification, which sharpens the availability question in
[spike 4](0004-admission-consistency-reverification.md) rather than answering it.

## The spikes

1. **[Provenance-chained four-eyes](0001-provenance-chained-four-eyes.md)** *(tier 2 publication, tier 3
   and 4 admission — size M)*. Prove that both deploy inputs descend from commits that passed
   multi-reviewer pull requests, and carry that proof where the cluster can check it. The primary option,
   because it reconstructs the control that tiers 0 and 1 use rather than substituting a different one.
2. **[Gate integrity](0002-gate-integrity.md)** *(tier 2 onward — size M)*. Prevent the change author from
   minting their own approval or weakening the rule that judges their change. Without this, spikes 1, 3,
   and 4 all produce forgeable results.
3. **[Publication-side policy gate](0003-publication-side-policy-gate.md)** *(tier 2 — size S)*. Run
   policy-as-code against the deploy payload before `flux push`, and harden
   `charts/archetype-backend/values.schema.json`, which currently permits an arbitrary registry and an
   arbitrary floating tag.
4. **[Admission-side consistency re-verification](0004-admission-consistency-reverification.md)** *(tiers 3
   and 4 — size M)*. Enumerate the checks that must run at admission for attested inputs to bind the
   admitted object. Any input fact that admission does not re-verify is a fact the gate does not enforce.
5. **[Evidence that the gate ran](0005-gate-decision-evidence.md)** *(tier 4 — size S)*. Determine whether
   denials reach durable `PolicyReport` storage, and what record demonstrates that the approval control
   operated on every deploy rather than merely existing.

Spikes 1 and 2 are the essential pair. Schedule spike 2 close behind spike 1, because an
unforgeable-approval design that turns out to be forgeable is not a partial result.

## Deliberately out of scope

The tier 2 README raises two further mitigations. These spikes exclude both by decision, because the
mandate is pre-exposure gating:

* **Progressive delivery with automatic rollback.** This limits the effect of a bad change after exposure
  rather than preventing it, which makes it a compensating control rather than a gate. Revisit it only if a
  change classification scheme arrives that makes a rollback-only path defensible for some class of change.
* **Sampled or after-the-fact human review.** This reintroduces the human intervention these spikes exist
  to remove.

## Showcase artifacts, not spikes

This repository demonstrates rather than runs, so some shortcomings are deliberate simplifications rather
than gaps in the tier design. The spikes record them where relevant, but they are not spike subjects:

* **No `CODEOWNERS` file.** The platform and application ownership split is conceptual here. In a real
  adoption, path-scoped ownership enforcement is what converts that split from a convention into an
  automated control. See [spike 2](0002-gate-integrity.md).
* **`datastoreEngine: memory` for SpiceDB, and Policy Reporter's SQLite on a kind `local-path` volume.**
  Storage choices suited to an ephemeral kind cluster. The design question they conceal, which is what
  evidence the gate must emit to be auditable, is [spike 5](0005-gate-decision-evidence.md).
* **The plaintext `showcase-authz-key` preshared key.** A demo credential. The design question behind it,
  which is how an enforcement point authenticates without a human handling a static token, appears in
  [spike 2](0002-gate-integrity.md).
