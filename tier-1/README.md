# Tier 1 — Flux reconciling raw manifests

Builds on [tier 0](../tier-0/README.md) (hand-applied raw manifests) by introducing GitOps
reconciliation itself, before anything else changes. The manifests are identical to tier 0's; the only
new concept is that Flux, not a human running `kubectl apply`, keeps the cluster in sync with this repo.

## What this tier demonstrates

* **`flux-operator` + `FluxInstance`** (`kind-cluster/flux.tf`): installs Flux via its OCI-hosted
  operator chart, then a `FluxInstance` CR tells `flux-operator` which controllers to run and which git
  repository/path to sync (`tier-1/manifests`, this GitHub repo, `main` branch).
  `flux-operator` translates that `sync` block into a `GitRepository` + `Kustomization` automatically —
  there's no need to hand-write those objects.
* **Same raw manifests as tier 0** (`manifests/namespace-apps.yaml`,
  `manifests/deployment-archetype-backend.yaml`, `manifests/service-archetype-backend.yaml`): still no
  Helm, still a hardcoded image tag.
* **The lesson**: "deploying" now means committing a change to `manifests/` and pushing — Flux notices
  and reconciles it, rather than a human running `kubectl apply` by hand. Drift between the cluster and
  the repo is now detected and corrected automatically.

## Directory layout

* `kind-cluster/` — OpenTofu stack: `kind_cluster` + `flux-operator`/`FluxInstance` only, no Kyverno.
* `manifests/` — the same plain Kubernetes objects as tier 0, now with a `kustomization.yaml` so Flux's
  `Kustomization` controller can apply them as a unit.
* `apps-source/` — `Dockerfile` and static content for the demo app (still built and pushed by hand).

## Getting started

```sh
cd tier-1/kind-cluster
mise install
./cluster.sh up      # Create the kind cluster (named tier-1), bootstrap Flux, verify health
./cluster.sh check
./cluster.sh down
```

### Verify

```sh
kubectl get kustomization -n flux-system
kubectl get pods -n apps
```

Edit `manifests/deployment-archetype-backend.yaml`, commit and push, then watch Flux pick it up:

```sh
flux reconcile kustomization flux -n flux-system --with-source
kubectl get deploy -n apps archetype-backend-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Progressing to tier 2

Tier 2 replaces the raw manifests with a Helm chart, introducing the platform/app split:

1. Platform engineering authors `charts/archetype-backend/` and publishes it to GHCR by SemVer.
2. `manifests/deployment-archetype-backend.yaml` and `manifests/service-archetype-backend.yaml` are
   deleted — the chart is now the only source of the workload's shape.
3. A `HelmRelease` sourced from that chart (via `chartRef: {kind: OCIRepository}`) replaces the raw
   objects in the synced directory, with the app's values inline in the `HelmRelease` for now.

See [`tier-2/README.md`](../tier-2/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
