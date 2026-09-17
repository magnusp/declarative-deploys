# Tier 2 — App-published values via OCI

Builds on [tier 1](../tier-1/README.md) (Helm chart + platform/app split) by letting the application
team deploy without ever committing to this cluster repository: they publish a values OCI artifact, and
Flux composes it with the platform chart automatically.

## What this tier demonstrates

* **App values become an OCI artifact**: `apps-source/values.yaml` is no longer committed into
  `clusters/kind/` (as it was, inline, in tier 1). Instead it's published as
  `oci://ghcr.io/magnusp/apps/archetype-backend-values:latest` by
  `.github/workflows/publish-app-values.yaml`, which also bumps `image.tag` to the newly built commit
  SHA.
* **Composition via `ArtifactGenerator`**
  (`clusters/kind/artifactgenerator-archetype-backend.yaml`): Flux's `source-watcher` merges the
  platform chart (`OCIRepository/archetype-backend`) with the app's published values
  (`OCIRepository/archetype-backend-values`) into a single `ExternalArtifact`.
* **Event-driven reconciliation, mostly**: the `HelmRelease` (`clusters/kind/helmrelease-archetype-backend.yaml`)
  now sources its chart from `chartRef: {kind: ExternalArtifact, ...}` instead of the OCI chart
  directly. `ArtifactGenerator` itself has no polling interval — it watches its sources — and
  helm-controller reacts to a new `ExternalArtifact` revision immediately, bypassing the `HelmRelease`'s
  own 10m interval. But the upstream `OCIRepository` for the `:latest` values tag still polls the
  registry on its own interval to notice a new digest, so the whole chain isn't push-triggered
  end-to-end — there's still up to one polling interval of latency between publishing and Flux noticing.

## ⚠️ Known risk introduced at this tier: no independent check on the change

Frameworks like ISO/IEC 27001 (via Annex A controls such as **A.8.32 Change management** and
**A.5.3 Segregation of duties**) treat this as two separate obligations: a change needs some
independent check before it reaches production, and the act of deploying it needs to be authorized and
logged. Neither obligation actually requires a human to click "approve" on every change — the standard
is risk-based, and "independent check" can be satisfied by automated gates as long as they're
appropriately designed and the person who authored the change isn't also the one who can bypass them.
Tiers 0 and 1 happen to satisfy the first obligation via git-commit/PR review (someone other than the
author reviews the diff before it merges), but that's one implementation of the control, not the
control itself.

**This tier removes whatever independent check existed upstream, without replacing it with
anything** — that's the actual gap, not "no human review" specifically. Deploy-time authorization and
logging stay fine even here: whoever triggers `publish-app-values.yaml` is an authenticated, logged
GitHub actor. What's missing is any check — human or automated — on *what* changed before
`oci://ghcr.io/magnusp/apps/archetype-backend-values:latest` (an OCI artifact — the same
container-registry mechanism used for images, here just holding a `values.yaml` instead) gets
published and Flux deploys it.

This is an acceptable trade-off for a demo focused on decoupling app deploys from git commits, but
it's a real compliance gap, not a cosmetic one. It stays open later in this progression too:

* **Tier 3 adds Kyverno, a Kubernetes *admission controller*** — software that sits in front of the
  Kubernetes API and inspects every object before it's allowed to be created or updated ("admitted"),
  with the power to approve, block, or modify it. Its SpiceDB-backed check strengthens **deploy-time
  authorization** ("is this identity allowed to deploy this service") and gives it an audit trail — a
  different control than a change check, and it doesn't substitute for one.
* **Tier 4's Kyverno policies verify image provenance** (base-image lineage, unforged revision
  annotations) — a fact about the artifact's *build history*, not about whether the values change was
  checked before it shipped.

**Mitigations that fit within this tier's own toolset, without borrowing Kyverno or SpiceDB from
later tiers, roughly in order of how well they preserve multiple-deploys-a-day velocity:**

* **Automated policy/schema checks as the gate.** `charts/archetype-backend/values.schema.json`
  already constrains what's structurally valid — extend that idea with a CI step in
  `publish-app-values.yaml` that runs policy-as-code checks (tools like `conftest`/Open Policy Agent
  evaluate a machine-readable policy against a file and fail the pipeline if it doesn't comply) against
  the rendered values before publishing. This is a deterministic, previously-approved check standing in
  for per-change human review — appropriate for routine, low-risk value bumps.
* **Machine-enforced segregation of duties.** Make sure the identity that performs the actual
  `flux push artifact` is a pipeline/service identity, never a human's standing credentials — so no
  individual author can single-handedly both write and ship a change outside the workflow, even
  without a per-change reviewer.
* **Progressive delivery with automated rollback as a compensating control.** Canary a rollout — shift
  traffic to the new version gradually and automatically complete or revert it based on health checks —
  using [Flagger](https://fluxcd.io/flagger/), a separate CNCF/Flux-family project (`HelmRelease` itself
  only supports install/upgrade remediation with retries and rollback on failure, not canary traffic
  shifting; Flagger additionally needs a service mesh or ingress controller to actually split traffic).
  This is a widely accepted substitute for pre-deploy human review in high-velocity continuous
  deployment, since it bounds the blast radius of an unreviewed bad change instead of trying to prevent
  it from ever shipping.
* **Human review, synchronous or sampled.** Route the values bump through a real PR with a required
  approving review (gates every change), or a GitHub Actions **environment with required reviewers**
  (a GitHub-native setting that pauses a workflow job after it's triggered until a designated person
  approves it — added via `environment: production` on the job that runs `flux push artifact`) — or,
  for lower-risk changes, review a statistically meaningful sample after the fact rather than gating
  every single one. This is the right tool when a change is high-risk or irreversible enough that
  automated gates and rollback aren't sufficient on their own — not the default answer for every
  deploy.

This repo doesn't implement any of these (each has real operational cost to maintain), but picking
one — matched to how risky your actual changes are — is the natural next step if you're adapting this
tier's pattern for real use.

## Directory layout

Same as tier 1, plus:

* `clusters/kind/ocirepository-archetype-backend-values.yaml` — tracks the `:latest` values artifact.
* `clusters/kind/artifactgenerator-archetype-backend.yaml` — the chart+values composition.

`apps-source/values.yaml` remains in the repo as the source the app team edits before running
`publish-app-values.yaml`, but it is no longer referenced directly by any `clusters/kind/` manifest.

## Getting started

```sh
cd tier-2
mise install

cd kind-cluster
./cluster.sh up      # Create the kind cluster (named tier-2), bootstrap Flux, verify health
./cluster.sh check
./cluster.sh down
```

### Simulate an application release

1. Run `.github/workflows/build-app-image.yaml` on your target commit.
2. Run `.github/workflows/publish-app-values.yaml` with `image_tag` set to that commit SHA.
3. Watch Flux pick it up without any commit to this repository:

   ```sh
   kubectl get ocirepository -n flux-system archetype-backend-values
   kubectl get externalartifact -n flux-system archetype-backend-demo
   kubectl get helmrelease -n flux-system archetype-backend-demo
   kubectl get deploy -n apps apps-archetype-backend-demo \
     -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

## Progressing to tier 3

Tier 3 adds a SpiceDB ReBAC admission gate:

1. **Kyverno** (`kind-cluster/kyverno.tf`) is introduced as the admission controller.
2. **SpiceDB** (`kind-cluster/spicedb-operator.tf`, `clusters/kind/spicedb-cluster.yaml`) runs
   ephemerally in-cluster, seeded from human-readable fixtures (`fixtures/spicedb/`).
3. `clusters/kind/clusterpolicy-spicedb-authz.yaml` checks, at admission time, whether the actor who
   built the app image (`dev.authz.app.deployer` label, stamped by `build-app-image.yaml` — already
   present on every image since tier 1, just unused until now) has `deploy` permission on the target
   service.

See [`tier-3/README.md`](../tier-3/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
