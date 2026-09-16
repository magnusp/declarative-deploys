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
* **Event-driven reconciliation**: the `HelmRelease` (`clusters/kind/helmrelease-archetype-backend.yaml`)
  now sources its chart from `chartRef: {kind: ExternalArtifact, ...}` instead of the OCI chart
  directly. Whenever either the chart version or the values artifact changes, a new `ExternalArtifact`
  revision is generated and the `HelmRelease` upgrades immediately — no polling interval to wait out,
  and no git commit for the app team to make.

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
2. **SpiceDB** (`clusters/kind/spicedb-operator.yaml`, `spicedb-cluster.yaml`) runs ephemerally
   in-cluster, seeded from human-readable fixtures (`fixtures/spicedb/`).
3. `clusters/kind/clusterpolicy-spicedb-authz.yaml` checks, at admission time, whether the actor who
   published the values artifact (`dev.authz.app.deployer` label, now stamped by
   `publish-app-values.yaml`) has `deploy` permission on the target service.

See [`tier-3/README.md`](../tier-3/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
