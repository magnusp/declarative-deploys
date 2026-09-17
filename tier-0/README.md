# Tier 0 — Flux + a deployer tool, raw manifests

This is the starting point for this progression, and it's meant to match a real baseline many
organizations already have: Flux is already reconciling a cluster repository, and a custom **deployer
tool** — not something in this repo, just described here — already automates getting manifests into
that repository. Nobody hand-edits YAML or runs `kubectl apply` by hand; the gap this progression closes
from here on is the platform/app split, not GitOps itself.

## What this tier demonstrates

* **The deployer tool** (described here, not implemented in this repo): triggered by a merge to an
  application repository's default branch, it optionally builds and tags a Docker image with the
  merge-derived version, and optionally deploys by templating Kubernetes manifests and git-committing
  them into this Flux-managed cluster repository (`manifests/`). Both steps are opt-in per app team, and
  neither publishes anything to an OCI registry — the only record of "what's deployed" is the commit the
  tool makes here.
* **`flux-operator` + `FluxInstance`** (`kind-cluster/flux.tf`): installs Flux via its OCI-hosted
  operator chart, then a `FluxInstance` CR tells `flux-operator` which controllers to run and which git
  repository/path to sync (`tier-0/manifests`, this GitHub repo, `main` branch). `flux-operator`
  translates that `sync` block into a `GitRepository` + `Kustomization` automatically.
* **Raw manifests, no Helm** (`manifests/namespace-apps.yaml`, `manifests/deployment-archetype-backend.yaml`,
  `manifests/service-archetype-backend.yaml`): whatever the deployer tool templates still lands here as
  plain `Deployment`/`Service` objects, not a chart. There's no platform/app ownership split yet — one
  set of manifests, templated and committed by one tool, covers the whole workload's shape and its
  environment-specific values together.
* **The lesson this tier sets up**: even with Flux and a deployer tool already automating the commit,
  "deploy" still means "a git commit to this repo," and the workload's shape (container, probes,
  resources) and its per-app values (image tag, replica count) are still the same undifferentiated
  templated output. Tier 1 splits those two concerns apart with a Helm chart.

## Directory layout

* `kind-cluster/` — OpenTofu stack: `kind_cluster` + `flux-operator`/`FluxInstance` only, no Kyverno.
* `manifests/` — plain Kubernetes objects, standing in for what the deployer tool would template and
  commit here, plus a `kustomization.yaml` so Flux's `Kustomization` controller can apply them as a unit.
* `apps-source/` — `Dockerfile` and static content for the demo app, standing in for the app repo the
  deployer tool's image-build step would run against.

## Getting started

```sh
cd tier-0/kind-cluster
mise install
./cluster.sh up      # Create the kind cluster (named tier-0), bootstrap Flux, verify health
./cluster.sh check
./cluster.sh down
```

### Verify

```sh
kubectl get kustomization -n flux-system
kubectl get pods -n apps
```

Simulate what the deployer tool would do on a merge — edit `manifests/deployment-archetype-backend.yaml`
(e.g. bump the image tag), commit and push, then watch Flux pick it up:

```sh
flux reconcile kustomization flux-system -n flux-system --with-source
kubectl get deploy -n apps archetype-backend-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Progressing to tier 1

Tier 1 replaces the raw manifests with a Helm chart, introducing the platform/app split:

1. Platform engineering authors `charts/archetype-backend/` and publishes it to GHCR by SemVer —
   independently of anything the deployer tool does.
2. `manifests/deployment-archetype-backend.yaml` and `manifests/service-archetype-backend.yaml` are
   gone — the chart is now the only source of the workload's shape.
3. A `HelmRelease` sourced from that chart (via `chartRef: {kind: OCIRepository}`) replaces the raw
   objects in the synced directory, with the app's values inline in the `HelmRelease` for now.

See [`tier-1/README.md`](../tier-1/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
