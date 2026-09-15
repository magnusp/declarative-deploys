# Tier 0 — Raw manifests, hand-applied (the worst case)

This is the baseline every other tier improves on: no GitOps, no Helm, no governance — just plain
Kubernetes manifests applied by hand against a kind cluster.

## What this tier demonstrates

* **A single flat set of manifests** (`manifests/namespace-apps.yaml`,
  `manifests/deployment-archetype-backend.yaml`, `manifests/service-archetype-backend.yaml`): one
  person or team owns everything — infrastructure, application shape, and configuration — with no
  separation of concerns.
* **No reconciler**: `./cluster.sh up` runs `kubectl apply -f manifests/` once, at cluster creation
  time. Nothing watches the cluster or the repo afterward. If someone runs `kubectl edit deployment` or
  `kubectl set image` directly against the live cluster, the change is silent, unaudited, and will
  silently diverge from whatever is committed here.
* **Hardcoded image tag**: `apps-source/Dockerfile` is built and pushed by hand
  (`ghcr.io/magnusp/apps/archetype-backend:manual`); there's no CI pipeline building or publishing it.
* **What "deploying a change" means here**: hand-edit a manifest, then re-run
  `kubectl apply -f manifests/` (or `./cluster.sh up` again) — or worse, patch the live object directly
  and never update the file at all.

This tier intentionally has no redeeming GitOps properties — every tier from here on fixes exactly one
of these problems.

## Directory layout

* `kind-cluster/` — OpenTofu stack: just `kind_cluster`, nothing else.
* `manifests/` — plain `Namespace`/`Deployment`/`Service` YAML.
* `apps-source/` — `Dockerfile` and static content for the demo app.

## Getting started

```sh
cd tier-0/kind-cluster
mise install
./cluster.sh up      # Create the kind cluster (named tier-0) and kubectl apply ../manifests/
./cluster.sh check
./cluster.sh down
```

### Verify

```sh
kubectl get pods -n apps
kubectl get deploy -n apps archetype-backend-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Try the failure mode directly: `kubectl set image deploy/archetype-backend-demo -n apps
archetype-backend-demo=ghcr.io/magnusp/apps/archetype-backend:some-other-tag` and note that nothing in
this repo reflects the change, and nothing will revert it.

## Progressing to tier 1

Tier 1 introduces Flux to reconcile these exact same manifests:

1. `kind-cluster/flux.tf` adds `flux-operator` and a `FluxInstance` synced to this GitHub repo.
2. `manifests/kustomization.yaml` is added so Flux's `Kustomization` controller can apply the directory
   as a unit.
3. No manifest content changes — the lesson at this step is purely "a reconciler now owns applying
   these files, a human no longer does."

See [`tier-1/README.md`](../tier-1/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
