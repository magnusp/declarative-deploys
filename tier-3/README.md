# Tier 3 — SpiceDB ReBAC admission gate

Builds on [tier 2](../tier-2/README.md) (app-published values via OCI) by adding an authorization check
at admission time: only actors with a `deploy` relationship on the target service, according to a
SpiceDB ReBAC graph, are allowed to have their Deployment admitted.

## What this tier demonstrates

* **Kyverno enters the picture** (`kind-cluster/kyverno.tf`): a Flux-managed `HelmRelease` sourced from
  Kyverno's OCI chart. This is the first tier with an admission controller.
* **Ephemeral in-cluster SpiceDB** (`clusters/kind/spicedb-operator.yaml`, `spicedb-operator-rbac.yaml`,
  `spicedb-cluster.yaml`): the SpiceDB Operator is reconciled from its upstream GitRepository, and a
  memory-backed `SpiceDBCluster` is created in the `authz` namespace.
* **Human-readable fixtures** (`fixtures/spicedb/schema.zed`, `fixtures/spicedb/relationships.txt`):
  a `Job` (`clusters/kind/spicedb-fixture-job.yaml`) loads these into SpiceDB on cluster bring-up.
  `scripts/spicedb-fixture.sh` lets you edit and re-apply them, or check permissions directly.
* **The admission gate** (`clusters/kind/clusterpolicy-spicedb-authz.yaml`): a Kyverno `ClusterPolicy`
  that reads the `dev.authz.app.deployer` label off the Deployment's container image (stamped by
  `publish-app-values.yaml` in CI) and calls SpiceDB's `/v1/permissions/check` API. If the deployer
  doesn't have `deploy` permission on the target service, the Deployment is rejected.
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
* `clusters/kind/spicedb-operator.yaml`, `spicedb-operator-rbac.yaml`, `spicedb-cluster.yaml`,
  `spicedb-fixture-job.yaml`, `clusterpolicy-spicedb-authz.yaml` — the ReBAC stack.
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

To see the gate actually reject a deploy, edit `fixtures/spicedb/relationships.txt` to remove
`magnusp`'s membership, re-apply with `./scripts/spicedb-fixture.sh apply`, then trigger a new values
publish — the `HelmRelease` upgrade will fail admission.

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
3. **Image base ancestor verification**: `clusterpolicy-verify-image-nginx-ancestor.yaml` cryptographically
   verifies the deployed image descends from an approved `nginx:1.27` base, regardless of intermediate
   build layers.
4. **Policy Reporter**: a dashboard and SQLite-backed audit trail for all Kyverno policy decisions.

See [`tier-4/README.md`](../tier-4/README.md) for the full detail, and the root
[README](../README.md#tiers) for the overall progression.
