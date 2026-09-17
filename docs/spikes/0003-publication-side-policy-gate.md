# Spike 3: Publication-side policy gate

* **Target tier:** tier 2
* **Enforcement point:** the `publish-app-values.yaml` workflow, before `flux push`
* **Size:** S
* **Controls:** A.8.9 (configuration management), A.8.28 (secure coding), A.8.32 (change management)

## Question

Which properties of the deploy payload can a deterministic, previously-approved rule set check before
publication — and what does that buy at a tier with no admission controller?

## Why the gap exists

Nothing validates the values artifact before it is published. `publish-app-values.yaml` accepts an
`image_tag` as a free-text `workflow_dispatch` input, writes it into `apps-source/values.yaml`, and pushes
the result. The chart's `values.schema.json` is the only constraint anywhere, and it is loose:

* **`image.repository`** is `"type": "string"` with `"minLength": 1`. Any registry, any repository. The
  deploy action can point the workload at an image nobody in this pipeline built.
* **`image.tag`** is likewise any non-empty string, so a mutable floating tag such as `latest` is valid —
  and is in fact what the checked-in `apps-source/values.yaml` contains.
* **`additionalProperties`** is not set to `false` at any level, so unrecognised keys pass silently.

Worth noting that `values.schema.json` *is* enforced in-cluster, because Helm validates it on install and
upgrade, so `helm-controller` will reject a non-conforming values payload. But that happens after
publication, and it surfaces as a failed `HelmRelease` rather than a clean pre-exposure rejection. The
artifact is already live in the registry and already the declared desired state. Tightening the schema is
therefore worth doing for its own sake, but it is not a gate.

## Investigation approach

**Tighten the schema.** Set `additionalProperties: false` throughout, constrain `image.repository` to an
allowlist pattern covering the registry paths this pipeline actually publishes to, and require `image.tag`
— noting that if the known-viable provenance verification in the [index](README.md#known-viable-work-that-precedes-the-spikes)
has already landed, the `image.repository` constraint is defence in depth rather than the primary control,
since an image not built by the platform's own workflow will fail admission at tiers 3 and 4 regardless of
what the values artifact claims. At tier 2 there is no such backstop, so here it remains primary.

Require `image.tag` to match an immutable form — a 40-character hex SHA or a `sha256:` digest. Expect this
to reveal that the
checked-in `apps-source/values.yaml` (`tag: "latest"`) violates the rule you want, which is informative
rather than inconvenient: it means the only way to produce a valid values artifact becomes the publish
workflow itself. Decide whether that forcing function is desirable or whether the repository default needs a
different representation.

**Add a policy-as-code check.** Run `conftest` or Open Policy Agent policies against the rendered values
in the workflow before `flux push`, covering the properties a JSON schema cannot express — cross-field
constraints, relationships between the requested image and the repository it came from, and any rule that
needs to consult external state.

**Establish the ceiling honestly.** This gate runs inside CI, so it binds only changes that travel through
CI. A direct push to the GHCR path bypasses it completely, and tier 2's `OCIRepository` has no `verify:`
block, so Flux will pull and deploy the bypassing artifact without complaint. Document that plainly: at tier
2 this is an advisory gate enforced by the honesty of the publication path, and closing the bypass requires
tier 3's admission controller.

**State the risk coverage.** Deterministic rules replace human judgement only for risks somebody enumerated
in advance. Novel risk passes unexamined, by construction. That is an acceptable and normal position for a
low-risk, high-frequency change class — but it should be written down as a scoping decision, not left to be
discovered later by whoever is answering an auditor.

## Done when

You have a tightened `values.schema.json`, a running policy check in the publish workflow that rejects a
payload pointing at an unapproved registry or a mutable tag, and a written statement of what the gate does
not cover — both the CI-bypass ceiling and the enumerated-risk limitation.
