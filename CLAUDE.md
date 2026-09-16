# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A demonstration of decoupled GitOps, presented as a progression of five isolated tiers
(`tier-0` … `tier-4`) rather than a single finished state. Each tier is a self-contained directory with
its own kind cluster / OpenTofu stack, peeling back capability from `tier-4` (platform-owned Helm charts
and cluster governance policies vs. application-owned source/values, composed at runtime by Flux) down
to `tier-0` (Flux already reconciling raw manifests that a custom deployer tool templates and commits —
the real-world baseline, not a from-scratch GitOps bootstrap). See the root README's
[Tiers](README.md#tiers) section for the full progression and what each tier introduces.

There is no application runtime to build/lint/test in the traditional sense — most "correctness" here
means valid Terraform/OpenTofu, valid Kubernetes/Flux/Kyverno YAML, and a cluster that reconciles to
`Ready`.

**Tiers are isolated by design** — nothing is shared or symlinked between `tier-N/` directories. If
you're changing something to fix a bug or improve clarity, check whether the same construct exists,
possibly in a stripped-down form, in adjacent tiers and needs the equivalent fix there too. Don't add
cross-tier abstractions (shared modules, common scripts) — duplication across tiers is intentional; it's
what lets each one be read and run independently.

## Commands

Tooling is version-pinned via `mise`, per tier (`tier-N/mise.toml` and `tier-N/kind-cluster/mise.toml`,
scoped down to only what that tier needs — e.g. `tier-0/kind-cluster/mise.toml` has no `helm`).

```sh
cd tier-N
mise install
```

Cluster lifecycle (always run from `tier-N/kind-cluster/`, via that tier's wrapper script — it manages
`KUBECONFIG` from OpenTofu output automatically, so don't export it manually):

```sh
cd tier-N/kind-cluster
./cluster.sh up      # tofu init + apply, then wait for readiness of whatever that tier bootstraps
./cluster.sh check   # just the readiness wait + status dump
./cluster.sh down    # tofu destroy
```

Each tier's `cluster.sh check` only waits on the components that tier actually installs (e.g. tier-0
just waits on Flux readiness; tier-2 waits on Flux only; tier-4 waits on Flux, Kyverno, Policy Reporter,
and SpiceDB). Don't copy a later tier's `check` logic into an earlier tier — that's how tiers end up
silently depending on components they don't have.

There's no separate `tofu plan`/`apply` workflow expected outside this script — treat `cluster.sh` as
the entry point rather than calling `tofu` directly.

SpiceDB fixture testing (tier-3 and tier-4 only; requires
`kubectl port-forward -n authz svc/spicedb 8443:8443` first):

```sh
cd tier-N
./scripts/spicedb-fixture.sh check <username>   # query /v1/permissions/check for the 'deploy' permission
./scripts/spicedb-fixture.sh apply              # push fixtures/spicedb/schema.zed + relationships.txt
```

Policy Reporter dashboard (tier-4 only):
`kubectl port-forward -n policy-reporter svc/policy-reporter-ui 8080:8080`.

## Architecture

Within any given tier that has them, these concerns are deliberately kept separate and never edited by
the same actor in the same workflow:

* **`tier-N/kind-cluster/`** — OpenTofu. Creates the kind cluster (named `tier-N`), then bootstraps
  `flux-operator` (via a `FluxInstance` CR) plus whatever subset of Kyverno and Policy Reporter that
  tier needs, as Flux-reconciled `OCIRepository`/`HelmRelease` pairs. Past cluster creation, resources
  are applied as `kubectl_manifest` YAML blocks, not native Terraform K8s resources — read the file
  before assuming a resource is a first-class `kubernetes_*`/`helm_release` type. `flux_git_path` points
  at that tier's own manifest directory (e.g. `tier-2/clusters/kind`), never another tier's.
* **`tier-N/charts/archetype-backend/`** (tier-1+) — the platform team's base Helm chart, published to
  `oci://ghcr.io/magnusp/charts/archetype-backend:<semver>`. From tier-4 onward it also includes a
  namespaced Kyverno `Policy` (`templates/policy.yaml`) that runs at admission time.
* **`tier-N/apps-source/`** — the simulated application repo: `Dockerfile`, static app content, and
  (tier-1+) `values.yaml`. From tier-2 onward, the app team never commits to `clusters/kind/`; they
  publish OCI artifacts instead (image + values), and Flux does the rest. At tier-0, a custom deployer
  tool (not implemented in this repo — described only in `tier-0/README.md`) templates manifests and
  commits them on the app team's behalf; there's no chart yet, so there's nothing to publish to a
  registry.
* **`tier-N/clusters/kind/`** (tier-1+; raw manifests live in `tier-0/manifests/` instead) — the GitOps
  manifests Flux reconciles. From tier-2 onward, `OCIRepository`/`ArtifactGenerator` objects compose the
  platform chart with the app-owned values into an `ExternalArtifact`, which feeds a `HelmRelease`.
  Cluster-wide `ClusterPolicy` objects (tier-3+) also live here, as opposed to the chart-packaged
  namespaced `Policy` (tier-4+).

**Key event chain to keep in mind when tracing a deploy (tier-2+)**: app team publishes
`ghcr.io/magnusp/apps/archetype-backend:<sha>` (image) and
`ghcr.io/magnusp/apps/archetype-backend-values:latest` (values) → `source-watcher`'s `ArtifactGenerator`
notices the values digest change and merges it with the platform base chart into an `ExternalArtifact` →
`helm-controller` reconciles the `HelmRelease` immediately (event-driven, not poll-interval-driven). At
tier-1, there's no `ArtifactGenerator` yet — the `HelmRelease` sources the chart's `OCIRepository`
directly and carries values inline, so it upgrades on Flux's normal poll interval instead. At tier-0,
there's no chart or `OCIRepository` at all — Flux reconciles whatever raw manifests the deployer tool
committed, on its normal poll interval.

**Governance (tier-3/tier-4) differs in scoping between the two tiers**: tier-3's
`clusterpolicy-spicedb-authz.yaml` is hardcoded to the `apps` namespace
(`match.any[].resources.namespaces: [apps]`). Tier-4 retrofits it — and adds
`clusterpolicy-disallow-manual-image-revision.yaml` and
`clusterpolicy-verify-image-nginx-ancestor.yaml` alongside it — to match on the
`governance.platform.io/managed: "true"` namespace label instead, so a single policy set applies to any
number of opt-in application workspaces. Don't backport tier-4's label-scoping into tier-3 or vice
versa; the difference between them is the point of that tier boundary.

When changing anything under a tier's `clusters/kind/` or `charts/archetype-backend/`, check whether the
change crosses that tier's platform/app boundary or (tier-3+) governance-scoping boundary described
above — that separation is the point of the tier, not an incidental detail.

## CI/CD workflows (`.github/workflows/`)

Workflows live at the repository root (a GitHub Actions requirement — they can't live per-tier and still
run), but each references `tier-4/` paths specifically and is only meaningful once you've reached the
tier that introduces the artifact it publishes (each workflow file has a comment noting this):

* `publish-chart.yaml` — platform chart → GHCR OCI, SemVer tag. Relevant from tier-1 onward.
* `build-app-image.yaml` — app image → GHCR, tagged with commit SHA, stamps
  `org.opencontainers.image.revision`/`vendor` and `dev.authz.app.deployer` labels. Relevant from tier-1
  onward.
* `publish-app-values.yaml` — bumps `image.tag` in `tier-4/apps-source/values.yaml` and pushes it as a
  `:latest` OCI artifact with deployer provenance annotations. Relevant from tier-2 onward.

These are manually triggered in sequence per the runbook in `tier-4/README.md`, not chained
automatically — don't assume merging to main alone deploys anything. If you add a new tier or renumber
existing ones, update these workflows' hardcoded `tier-4/...` paths accordingly.
