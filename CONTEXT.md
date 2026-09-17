# Context

Glossary of the domain language used across this repository's documentation. Terms only — the
progression narrative lives in [`docs/spikes/README.md`](docs/spikes/README.md), and decisions live in
[`docs/adr/`](docs/adr/).

## Framing

### Spike

A time-boxed investigation, not an implementation. Two kinds are tracked separately, because their
definitions of "done" differ:

* **Tech spike** — ends in a recommendation or a working proof-of-concept.
* **Compliance spike** — ends in a gap analysis against named controls, not code.

Work whose mechanism is already confirmed is not a spike. It is implementation, however small.

### Tier-design gap

A shortcoming of the tier *pattern*: it has no automated control for something, and any real adopter of
the pattern inherits the gap. This is what spikes target.

### Showcase artifact

A deliberate simplification that exists only because this repository is a demonstration — in-memory
datastores, plaintext demo credentials, single-node storage, or conventions left unenforced. A real
adoption would do otherwise, so it is not spike material. It is still documented, alongside the
automated control it stands in for, so a reader can tell "conceptual here" from "missing from the
pattern".

One observation can split across both. The plaintext SpiceDB preshared key is a showcase artifact,
whereas "how does an enforcement point authenticate to the authorization service without a human
handling the credential?" is a tier-design gap. Spike the design question, and document the shortcut.

## Controls

### Four-eyes principle

Someone other than the change author approves the change before it takes effect. At tiers 0 and 1 this
is satisfied incidentally by pull request review, with the git history as its evidence.

### Change check

An independent check on *what changed* before it ships. Answers **was this change examined?** Satisfied
by an automated policy gate, a progressive-delivery health check, or human review. This is the
obligation tier 2 removes and no later tier restores.

### Build-time provenance

A verifiable trail of how an artifact was built and from what, such as a SLSA provenance attestation or
base-image ancestry. Answers **where did this come from?**

### Deploy-time authorization

Whether the acting identity is permitted to deploy this workload — the SpiceDB ReBAC admission gate.
Answers **was this actor allowed?**

These three are distinct obligations and none substitutes for another. The tier READMEs keep them
separate, and documentation here follows suit.

### Pre-exposure gate

A control that prevents a non-conforming change from reaching production, as opposed to one that bounds
the damage after exposure. Canary deployment with automatic rollback is not a pre-exposure gate; it is a
compensating control.

## Mechanisms

### Enforcement point

The component that can allow, block, or modify a change at the moment it is applied — at tiers 3 and 4,
the Kyverno admission webhook.

### Fact producer

The upstream component that creates the evidence an enforcement point evaluates, such as a CI workflow
or a signer. An enforcement point can only enforce facts a fact producer actually produced; it cannot
retroactively supply a check that never happened.

### Gate integrity

The property that the party whose change a gate judges cannot alter that gate. It has two halves: the
**gate definition**, which lives on a platform-owned path protected by path-scoped review requirements,
and the **gate's signing identity**, which is bound to a specific platform-owned workflow so that no
other workflow can mint an equivalent-looking attestation. A gate the gated party can weaken is not a
weaker control; it is not a control.

## Lifecycles

Changes in tiers 2 through 4 travel two separate paths, with different controls and different
classifications. Conflating them is the most common way to misread the gap.

### Code and configuration lifecycle

Application code, the `Dockerfile`, the platform chart, cluster manifests, and the checked-in
`values.yaml`. Always gated behind a pull request with multiple reviewers. Human four-eyes review is
retained here and is not in question.

### Deploy lifecycle

The act of publishing the values OCI artifact that rolls a new image into the cluster. Carries a single
change classification, involves no human approval, and is the lifecycle the spikes target.

The two are less cleanly separated than they appear, because the values artifact that deploys is not the
values file anyone reviewed.

## Reference

### Annex A Clause 8

Control references in these documents point at ISO/IEC 27001:2022 Annex A, Clause 8 ("Technological
controls") — the control family most relevant to high-velocity continuous delivery. No real
certification is in scope for this repository; the framing gives the documentation a well-known
reference point instead of bespoke compliance language.
