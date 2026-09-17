# Tier 3 — SpiceDB ReBAC admission gate

Builds on [tier 2](../tier-2/README.md) (app-published values via OCI) by adding an authorization check
at admission time: only actors with a `deploy` relationship on the target service, according to a
SpiceDB ReBAC graph, are allowed to have their Deployment admitted.

## What this tier demonstrates

* **Kyverno enters the picture** (`kind-cluster/kyverno.tf`): a Flux-managed `HelmRelease` sourced from
  Kyverno's OCI chart. This is the first tier with an admission controller.
* **Ephemeral in-cluster SpiceDB Operator bootstrap** (`kind-cluster/spicedb-operator.tf`): applied
  directly via OpenTofu, not the git-synced Flux `Kustomization` — the operator's `GitRepository` and
  its own `Kustomization` install the `SpiceDBCluster` CRD, which `clusters/kind/spicedb-cluster.yaml`
  (a resource of that CRD) depends on existing. Bundling both in the same git-synced `Kustomization`
  would deadlock on a cold cluster: Flux validates the whole manifest set together, so the CR's failed
  dry-run (no CRD yet) would block the operator's own bootstrap objects from ever being created.
* **Human-readable fixtures** (`fixtures/spicedb/schema.zed`, `fixtures/spicedb/relationships.txt`):
  a `Job` (`clusters/kind/spicedb-fixture-job.yaml`) loads these into SpiceDB on cluster bring-up.
  `scripts/spicedb-fixture.sh` lets you check permissions directly, add/update relationships (`apply`),
  or explicitly revoke one (`revoke`) — `apply` only ever upserts, so editing a tuple out of
  `relationships.txt` and re-applying does **not** remove it.
* **The admission gate** (`clusters/kind/clusterpolicy-spicedb-authz.yaml`): a Kyverno `ClusterPolicy`
  that reads the `dev.authz.app.deployer` label off the Deployment's container image — stamped by
  `.github/workflows/build-app-image.yaml` when the image is built, not by `publish-app-values.yaml`
  (which stamps an identically-named OCI artifact *annotation* on the values artifact, which this
  policy never reads) — and calls SpiceDB's `/v1/permissions/check` API over `apiCall.service` (an
  in-cluster HTTP service call; Kyverno's `apiCall.urlPath` addresses only the Kubernetes API server
  and can't be used here). If the deployer doesn't have `deploy` permission on the target service, or
  the image carries no deployer identity at all, the Deployment is rejected — the gate fails closed.
* **Deliberately not yet generalized**: this policy is scoped directly to the `apps` namespace
  (`namespaces: [apps]`) rather than an opt-in label. Tier 4 introduces
  `governance.platform.io/managed` label scoping and retrofits this policy to use it, once there's a
  second governance concern to justify generalizing.

## This tier strengthens deploy authorization, not the change check

Tier 2's README distinguishes two obligations: an independent check on *the change* before it's
published (which can be automated, sampled, or human — see tier 2 for the options), and authorization
plus logging of *the deploy action*. Kyverno — a Kubernetes *admission controller*, meaning it inspects
every object Kubernetes is about to create or update and can allow, block, or modify it before that
happens — enters the picture here, but it only strengthens the second obligation, not the first.

Specifically: the `clusterpolicy-spicedb-authz.yaml` `ClusterPolicy` runs at *admission time* (the
moment a `Deployment` is submitted, before Kubernetes persists it) and calls out to **SpiceDB**, a
*relationship-based access control (ReBAC)* system — instead of a fixed list of roles, it stores a
graph of relationships (e.g. "`magnusp` can `deploy` `archetype-backend`") and answers permission
questions by querying that graph. The policy asks SpiceDB **"is this identity allowed to deploy this
service,"** and Kyverno logs the answer — that's deploy-time authorization and auditability. It has no
way to answer **"was the values change checked before `magnusp` published it,"** because that's a fact
about the change, not the actor, and nothing in this pipeline records it. A fully authorized deployer
can still publish arbitrary, unchecked values and have them admitted — SpiceDB has no opinion on
content, only on who pushed it.

## Directory layout

Same as tier 2, plus:

* `kind-cluster/kyverno.tf` — Kyverno bootstrap.
* `kind-cluster/spicedb-operator.tf` — SpiceDB Operator bootstrap (`GitRepository` + `Kustomization` +
  RBAC extension), applied via OpenTofu rather than the git-synced manifests, for the ordering reason
  above.
* `clusters/kind/spicedb-cluster.yaml`, `spicedb-fixture-job.yaml`, `clusterpolicy-spicedb-authz.yaml` —
  the rest of the ReBAC stack.
* `fixtures/spicedb/` and `scripts/spicedb-fixture.sh`.

## Getting started

```sh
cd tier-3
mise install

cd kind-cluster
./cluster.sh up      # Create the kind cluster (named tier-3), bootstrap Flux and Kyverno, verify health
./cluster.sh check
./cluster.sh down
```

### Verify the admission gate

```sh
# Port-forward SpiceDB's HTTP API
kubectl port-forward -n authz svc/spicedb 8443:8443

# magnusp is granted deploy permission by the seeded fixtures
../scripts/spicedb-fixture.sh check magnusp

# unauthorized-dev has no relationship to the service and will be denied
../scripts/spicedb-fixture.sh check unauthorized-dev

# Inspect the running deployment
kubectl get deploy -n apps apps-archetype-backend-demo
```

To see the gate actually reject a deploy, revoke `magnusp`'s permission — `apply` only upserts, so
removing a line from `relationships.txt` and re-applying has no effect:

```sh
../scripts/spicedb-fixture.sh revoke magnusp
kubectl delete deployment apps-archetype-backend-demo -n apps
```

The delete itself gets blocked at admission with the SpiceDB rejection message. Restore access and
recover with:

```sh
../scripts/spicedb-fixture.sh apply
flux reconcile helmrelease archetype-backend-demo -n flux-system --force
```

## Progressing to tier 4

Tier 4 adds:

1. **Governance label scoping**: `namespace-apps.yaml` gains the `governance.platform.io/managed: "true"`
   label, and this tier's `clusterpolicy-spicedb-authz.yaml` is retrofitted to match on that label
   (`namespaceSelector`) instead of a hardcoded namespace name — making the policy reusable across any
   number of opt-in application workspaces.
2. **Image revision integrity**: `clusterpolicy-disallow-manual-image-revision.yaml` (blocks forged
   annotations) plus a namespaced Kyverno `Policy` packaged inside the chart itself
   (`charts/archetype-backend/templates/policy.yaml`) that injects the real
   `org.opencontainers.image.revision` at admission time.
3. **Image base ancestor check**: `clusterpolicy-verify-image-nginx-ancestor.yaml` compares the
   deployed image's rootfs layer digests against a known-good `nginx:1.27` base layer digest — a
   layer-hash allowlist, not a signature or attestation check (see tier-4's README for the distinction
   and a real attestation-based alternative).
4. **Policy Reporter**: a dashboard and SQLite-backed audit trail for all Kyverno policy decisions.

See [`tier-4/README.md`](../tier-4/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
