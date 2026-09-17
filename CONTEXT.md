# Declarative Deploys

Context for a showcase repository that demonstrates decoupled GitOps as a progression of five tiers. This
glossary covers the compliance vocabulary the progression needs, because tier 2 removes a change-approval
control that no later tier restores.

The progression narrative and its architectural decisions live in
[`docs/spikes/README.md`](docs/spikes/README.md).

## Language

### Investigation

**Spike**:
A time-boxed investigation that produces a recommendation or a gap analysis, never shipped code. Work whose
mechanism is already confirmed is implementation, not a spike.
_Avoid_: task, story, epic

**Tech spike**:
A spike that ends in a technical recommendation or a proof-of-concept.
_Avoid_: technical investigation, POC ticket

**Compliance spike**:
A spike that ends in a gap analysis against named controls.
_Avoid_: audit task, compliance review

**Tier-design gap**:
A shortcoming of the tier pattern itself, which any real adopter of the pattern inherits. Spikes target
these.
_Avoid_: bug, flaw, technical debt

**Showcase artifact**:
A simplification that exists only because this repository demonstrates rather than runs, such as an
in-memory datastore or a plaintext demo credential. Documented, never spiked.
_Avoid_: shortcut, hack, known issue

### Controls

**Four-eyes principle**:
The requirement that someone other than the change author approves a change before it takes effect. Tiers 0
and 1 satisfy it through pull request review.
_Avoid_: peer review, sign-off, dual control

**Change check**:
A control that answers whether a change was examined before it shipped. Tier 2 removes this obligation and
no later tier restores it.
_Avoid_: review, validation, QA

**Build-time provenance**:
A verifiable record of how an artifact was built and from what, such as a Supply-chain Levels for Software
Artifacts (SLSA) attestation. Answers where an artifact came from, not whether anyone examined it.
_Avoid_: build metadata, audit trail

**Deploy-time authorization**:
A control that answers whether the acting identity may deploy a given workload. Tier 3 implements it as a
relationship-based access control (ReBAC) check against SpiceDB.
_Avoid_: permission check, access control

**Pre-exposure gate**:
A control that stops a non-conforming change before it reaches production, as distinct from one that limits
the damage afterward. Canary deployment with automatic rollback is not one.
_Avoid_: guardrail, gate, check

### Mechanisms

**Enforcement point**:
The component that allows, blocks, or modifies a change at the moment it is applied. At tiers 3 and 4, the
Kyverno admission webhook.
_Avoid_: policy engine, admission controller

**Fact producer**:
The upstream component that creates the evidence an enforcement point evaluates, such as a continuous
integration workflow or a signer. An enforcement point cannot supply a fact that no producer created.
_Avoid_: attestor, signer, source

**Gate integrity**:
The property that the party whose change a gate judges cannot alter that gate. It covers both the gate
definition and the gate's signing identity.
_Avoid_: policy security, tamper protection

### Lifecycles

**Code and configuration lifecycle**:
The path taken by application code, the platform chart, cluster manifests, and the checked-in `values.yaml`.
Always gated behind a pull request with multiple reviewers.
_Avoid_: source lifecycle, dev workflow

**Deploy lifecycle**:
The path taken by the act of publishing the values artifact that rolls a new image into the cluster. Carries
one change classification and involves no human approval.
_Avoid_: release, rollout, promotion

## Flagged ambiguities

**"Approval" means two different things.** In the code and configuration lifecycle it means a human
reviewer approving a pull request. In the deploy lifecycle it means a machine-issued attestation that a
check passed. Always name the lifecycle when the distinction matters.

**"Provenance" does not imply examination.** Build-time provenance and a change check answer different
questions, and the repository's tier READMEs keep them separate. Treating a provenance attestation as
evidence of approval is the most common way to misread the gap.

**"Gate" is overloaded.** Reserve pre-exposure gate for controls that block a change before production, and
name compensating controls explicitly.

## Reference

Control references in this repository's documentation point at ISO/IEC 27001:2022 Annex A, Clause 8
("Technological controls"). No certification is in scope here. The framing gives the documentation a
well-known reference point instead of bespoke compliance language.

## Example dialogue

**Developer**: The image is signed and the build provenance is attested, so the deploy is approved, right?

**Auditor**: Those are different claims. Build-time provenance tells me the artifact came from your
workflow. It does not tell me anyone examined the change.

**Developer**: The SpiceDB check runs at admission though. Doesn't that approve it?

**Auditor**: That is deploy-time authorization. It tells me the actor was allowed to deploy. I still need a
change check: did anything examine what changed before it shipped?

**Developer**: At tier 1 the pull request covered that. Tier 2 publishes an artifact instead, so there is no
pull request.

**Auditor**: Then tier 2 dropped the control. To replace four-eyes review without a human, you need a fact
producer that issues an attestation when a check passes, and an enforcement point that refuses the deploy
without it.

**Developer**: The app team's workflow could issue that attestation.

**Auditor**: Then the gated party mints its own approval. That breaks gate integrity, and the control stops
being a control.
