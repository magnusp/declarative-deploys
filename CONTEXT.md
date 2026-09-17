# Context

## Glossary

### Spike
A time-boxed investigation, not an implementation. Two distinct kinds are tracked separately in this repo, with different definitions of "done":

* **Tech spike** — a technical investigation ending in a recommendation or a working proof-of-concept (e.g., "can `ArtifactGenerator` merge three value sources instead of two?").
* **Compliance spike** — an investigation into whether an existing or proposed control satisfies an external requirement, ending in a gap analysis against named clauses/controls, not code.

### ISO 27001 scope for this repo's spikes
Spikes drafted against tier-2 through tier-4 are framed as *invented, plausible* support for **ISO/IEC 27001:2022 Annex A, Clause 8 ("Technological controls")** — the control family most relevant to high-velocity continuous delivery (e.g., 8.9 configuration management, 8.16 monitoring, 8.25 secure development lifecycle, 8.28 secure coding, 8.31 separation of environments, 8.32 change management). This repo has no real ISO certification in scope; the framing exists to give the spikes a concrete, well-known reference point rather than inventing bespoke compliance language.

### Spike framing: progression, tagged by tier
Spikes are written as a **progression narrative** — how governance/control maturity increases as the repo's tier progression moves from tier-2 to tier-4 — rather than five independent per-tier gap analyses. Each individual spike is still **tagged with the tier it targets**, so the narrative reads tier-by-tier even though the throughline is continuous (mirrors the "peeling back capability" framing already used for the tiers themselves).

### The gap the spikes exist to close
Tiers 0 and 1 satisfy ISO 27001 through **PR review and approval under the four-eyes principle** — a human other than the author approves the change before it merges, and the git history is the evidence. Tiers 2 through 4 remove that control: the app team publishes OCI artifacts instead of committing, so no PR exists to review and no human approves anything.

The spikes therefore target exactly one objective: **automated change attestation and approval, without human intervention** — machine-issued evidence that a change was checked and sanctioned, enforceable at deploy time. Supply-chain provenance, deploy-time authorization, and audit-trail plumbing are in scope only insofar as they serve that objective.

### Two lifecycles
Changes in tiers 2 through 4 travel two separate paths, with different controls and different classifications. Conflating them is the most common way to misread the gap:

* **Code and configuration lifecycle** — application code, `Dockerfile`, the platform chart, cluster manifests, and the checked-in `values.yaml`. Always gated behind a pull request with multiple reviewers. Human four-eyes is retained here and is not in question.
* **Deploy lifecycle** — the act of publishing the values OCI artifact that rolls a new image into the cluster. Carries a single change classification, involves no human approval, and is the lifecycle the spikes target.

The two are not as cleanly separated as they appear: `publish-app-values.yaml` mutates `image.tag` in the working copy at publish time and never commits it, so the values artifact that deploys is **not** the values file that was reviewed. The deploy lifecycle's payload is unreviewed by construction.

### Gate integrity
A pre-exposure gate is only a control if the party whose change it gates cannot alter it. Automated gate integrity has two halves:

* **The gate definition** lives on a platform-owned path, protected by path-scoped review requirements, so a change author cannot weaken the rule that judges their change.
* **The gate's signing identity** is bound to a specific platform-owned workflow (via OIDC subject claims), so an app team cannot mint an equivalent-looking attestation from a workflow they control.

### Three distinct controls (do not conflate)
The tier READMEs are careful to keep these separate, and spike language must follow suit — each satisfies a different obligation, and none substitutes for another:

* **Build-time provenance** — a verifiable trail of how an artifact was built and from what (e.g. SLSA provenance attestation, base-image ancestry). Answers *where did this come from?*
* **Change check** — an independent check on *what changed* before it ships (automated policy gate, progressive-delivery health check, or human review). Answers *was this change examined?* This is the obligation tier-2 removes and no later tier restores.
* **Deploy-time authorization** — whether the acting identity is permitted to deploy this workload (the SpiceDB ReBAC admission gate). Answers *was this actor allowed?*

### Tier-design gap vs. showcase artifact
This repository is a **showcase**, so two very different kinds of shortcoming live side by side, and only one of them is spike material:

* **Tier-design gap** — the tier *pattern* has no automated control for something, and any real adopter of the pattern would inherit that gap. This is what spikes target.
* **Showcase artifact** — a deliberate simplification that exists only because this is a demonstration (in-memory datastores, plaintext demo credentials, single-node storage, conventions left unenforced). A real deployment would obviously do otherwise, so it isn't a spike. It is still **documented**, explaining which automated control it stands in for, so a reader understands the difference between "conceptual here" and "missing from the pattern."

A single observation can split across both: the plaintext SpiceDB preshared key is a showcase artifact, but "how does the enforcement point authenticate to the authorization service without a human handling the credential?" is a tier-design gap. Spike the design question; document the shortcut.

### Enforcement point
The component that can allow, block, or modify a change at the moment it is applied — in tiers 3 and 4, the Kyverno admission webhook. Distinct from the **fact producer** upstream (CI workflow, signer) that creates the evidence an enforcement point evaluates. Kyverno can only enforce facts produced and signed upstream; it cannot retroactively supply a check that never happened.

### Spike location
Spikes live under root-level `docs/spikes/`, **not** inside any `tier-N/` directory — this keeps the cross-tier progression narrative from violating the repo's tier-isolation principle (no shared/symlinked content between tiers). Structure: `docs/spikes/README.md` as the progression-narrative index, plus one numbered file per spike (e.g. `docs/spikes/0001-title.md`), ADR-adjacent in style but a distinct series from `docs/adr/`.
