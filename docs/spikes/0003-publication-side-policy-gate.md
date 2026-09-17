# Spike 3: Publication-side policy gate

* **Target tier:** tier 2
* **Enforcement point:** the `publish-app-values.yaml` workflow, before `flux push`
* **Size:** S
* **Controls:**
  * A.8.9 — configuration management
  * A.8.28 — secure coding
  * A.8.32 — change management

## Question

Which properties of the deploy payload can a deterministic, pre-approved rule set check before publication,
and what does that achieve at a tier with no admission controller?

## Why the gap exists

Nothing validates the values artifact before publication. `publish-app-values.yaml` accepts an `image_tag`
as a free-text `workflow_dispatch` input, writes it into `apps-source/values.yaml`, and pushes the result.
The chart's `values.schema.json` is the only constraint anywhere, and it is loose:

* **`image.repository`** is a string with `"minLength": 1`. Any registry and any repository pass, so the
  deploy action can point the workload at an image that nothing in this pipeline built.
* **`image.tag`** is likewise any non-empty string, so a mutable floating tag such as `latest` passes. The
  checked-in `apps-source/values.yaml` contains exactly that.
* **`additionalProperties`** is unset at every level, so unrecognized keys pass without comment.

Helm validates `values.schema.json` on install and upgrade, so `helm-controller` does reject a
non-conforming values payload in the cluster. That happens after publication, and it surfaces as a failed
`HelmRelease` rather than a clean pre-exposure rejection. By then the artifact is live in the registry and
is already the declared desired state. Tightening the schema is worthwhile on its own, but it is not a
gate.

## Investigation approach

### Tighten the schema

Set `additionalProperties: false` throughout. Constrain `image.repository` to an allowlist pattern covering
the registry paths this pipeline publishes to. Require `image.tag` to match an immutable form, either a
40-character hex SHA or a `sha256:` digest.

If the provenance verification in the known-viable work section of the [index](README.md) has already
landed, the `image.repository` constraint becomes a secondary control rather than the primary one, because
an image the platform's own workflow did not build fails admission at tiers 3 and 4 whatever the values
artifact claims. Tier 2 has no such secondary control, so the constraint stays primary there.

Expect the tag rule to reject the checked-in `apps-source/values.yaml`, which specifies `tag: "latest"`.
That result is informative: it means the publish workflow becomes the only way to produce a valid values
artifact. Decide whether that consequence is desirable, or whether the repository default needs a different
representation.

### Add a policy-as-code check

Run `conftest` or Open Policy Agent policies against the rendered values in the workflow before
`flux push`. Cover the properties a JSON schema cannot express: cross-field constraints, relationships
between the requested image and the repository it came from, and any rule that needs external state.

### Establish the limit honestly

This gate runs inside CI, so it binds only changes that travel through CI. A direct push to the GHCR path
bypasses it, and tier 2's `OCIRepository` carries no `verify:` block, so Flux pulls and deploys the
bypassing artifact. Document that plainly: at tier 2 this is an advisory gate that depends on the
publication path being used, and closing the bypass requires the admission controller that tier 3
introduces.

### State the risk coverage

Deterministic rules replace human judgment only for risks that someone enumerated in advance. Novel risk
passes unexamined. That is a normal and defensible position for a low-risk, high-frequency change class,
but record it as a scoping decision. Otherwise whoever answers an auditor discovers it later.

## Done when

You have a tightened `values.schema.json`, a policy check in the publish workflow that rejects a payload
pointing at an unapproved registry or a mutable tag, and a written statement of what the gate does not
cover. That statement needs both limits: the CI bypass and the enumerated-risk boundary.
