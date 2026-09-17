# Tier 1 — Helm chart and the platform/app split

Builds on [tier 0](../tier-0/README.md) (Flux + a deployer tool, raw manifests) by introducing the core
lesson of this whole progression: **chart-authoring and values-authoring are different jobs**, decoupled
by publishing the chart to an OCI registry.

## What this tier demonstrates

* **Platform engineering owns a Helm chart** (`charts/archetype-backend/`): a `Deployment` + `Service`
  template, published to `oci://ghcr.io/magnusp/charts/archetype-backend:<semver>` by
  `.github/workflows/publish-chart.yaml`.
* **The chart is tracked by an `OCIRepository`** (`clusters/kind/ocirepository-archetype-backend.yaml`),
  polled on Flux's normal interval — no event-driven composition yet, that's tier 2.
* **Application team owns deployment parameters, but not yet a publishing pipeline for them**: the
  `HelmRelease` (`clusters/kind/helmrelease-archetype-backend.yaml`) sources its chart directly via
  `chartRef: {kind: OCIRepository, name: archetype-backend}` and carries the app's values inline under
  `spec.values`. `apps-source/values.yaml` still documents what those values should be, but at this tier
  it's a reference a human copies from, not something CI publishes.
* **What's gone from tier 0**: the raw `Deployment`/`Service` manifests and the deployer tool's role in
  templating them. The chart is now the only source of the workload's shape; the app team (or the
  deployer tool acting on its behalf) can no longer diverge from the platform's container/probe/resource
  conventions baked into the chart template.

## Directory layout

* `kind-cluster/` — OpenTofu stack (kind cluster named `tier-1` + Flux, no Kyverno).
* `charts/archetype-backend/` — the platform-owned chart.
* `clusters/kind/` — `namespace-apps.yaml`, `ocirepository-archetype-backend.yaml`,
  `helmrelease-archetype-backend.yaml`.
* `apps-source/` — `Dockerfile`, static content, and `values.yaml` (reference only at this tier).

## Getting started

```sh
cd tier-1
mise install

cd kind-cluster
./cluster.sh up      # Create the kind cluster (named tier-1), bootstrap Flux, verify health
./cluster.sh check
./cluster.sh down
```

### Verify

```sh
kubectl get ocirepository -n flux-system archetype-backend
kubectl get helmrelease -n flux-system archetype-backend-demo
kubectl get deploy -n apps apps-archetype-backend-demo
```

No workflow publishes an image tagged `:latest` — `build-app-image.yaml` only ever pushes
`:${{ github.sha }}` — so `helmrelease-archetype-backend.yaml`'s inline `image.tag: "latest"` will sit
in `ImagePullBackOff` on a fresh cluster unless you build and load one yourself:

```sh
docker build -t ghcr.io/magnusp/apps/archetype-backend:latest ../apps-source
kind load docker-image ghcr.io/magnusp/apps/archetype-backend:latest --name tier-1
```

To roll out a new chart version, run `.github/workflows/publish-chart.yaml` with a bumped SemVer tag,
then bump `clusters/kind/ocirepository-archetype-backend.yaml`'s `spec.ref.tag` to match and commit it;
Flux picks up the new chart on its next poll (or `flux reconcile source oci archetype-backend`).

## Progressing to tier 2

Tier 2 removes the need for the app team to hand-copy values or wait for a poll interval:

1. `apps-source/values.yaml` becomes something CI publishes — `.github/workflows/publish-app-values.yaml`
   pushes it to `oci://ghcr.io/magnusp/apps/archetype-backend-values:latest` after bumping `image.tag`.
2. `clusters/kind/ocirepository-archetype-backend-values.yaml` tracks that artifact.
3. `clusters/kind/artifactgenerator-archetype-backend.yaml` composes the chart and the published values
   into an `ExternalArtifact`, and the `HelmRelease`'s `chartRef` switches from the raw chart
   `OCIRepository` to that `ExternalArtifact` — giving immediate, event-driven reconciliation whenever
   either changes, and letting the app team deploy without a single git commit to this repository.

See [`tier-2/README.md`](../tier-2/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
