# Spike 1: Provenance-chained four-eyes

* **Target tier:** tier 2 (publication), tiers 3 and 4 (admission)
* **Enforcement point:** the CI workflow at tier 2; the Kyverno admission webhook at tiers 3 and 4
* **Size:** M (reduced from L — the enforcement mechanics below are now verified rather than open)
* **Controls:** A.8.32 (change management), A.8.25 (secure development lifecycle), A.8.4 (access to source code), A.5.3 (segregation of duties)

## Question

Can you prove, automatically and at deploy time, that everything reaching the cluster descends from a commit
that passed a pull request with the required number of independent approvals — and reject the deploy when it
does not?

If this works, tiers 2 through 4 do not *substitute* a new control for four-eyes review. They carry the
existing one forward, machine-verified, into a delivery model that has no pull request of its own.

## Why the gap exists

Tier 2 splits delivery from git. The application team publishes
`ghcr.io/magnusp/apps/archetype-backend:<sha>` and
`ghcr.io/magnusp/apps/archetype-backend-values:latest`, and Flux deploys whatever appears there. The commit
SHA in the image tag *hints* at provenance, but nothing checks it, and nothing anywhere records whether that
commit was ever reviewed.

The values artifact is worse. `publish-app-values.yaml` rewrites `image.tag` with
`yq -i '.image.tag = strenv(IMAGE_TAG)'` and never commits the result, taking `IMAGE_TAG` from a free-text
`workflow_dispatch` input. The reviewed file in the repository says `tag: "latest"`. So the values payload
that deploys has no reviewed counterpart at all — reviewing `apps-source/values.yaml` reviews a file that is
mutated after approval and before publication.

## Investigation approach

**Produce the fact.** At build and publish time, have the workflow query the approval state of the commit it
is building (`GET /repos/{owner}/{repo}/commits/{sha}/pulls`, then the pull request's reviews) and emit a
signed attestation with a custom predicate — `actions/attest` with a `predicate-type` of your own, or
`cosign attest`. Note this is a different action from the `actions/attest-build-provenance` already used in
both workflows, which only produces SLSA provenance and says nothing about review.

The predicate needs at minimum the commit SHA, the pull request number, the approving reviewer identities,
the approval count, the base branch, and the commit author — enough for a gate to evaluate *independence*,
not merely *count*. Snapshot the branch protection or ruleset requirements in force at merge time too, since
repository settings can be relaxed afterwards and a predicate that merely asserts "the rules were satisfied"
becomes unfalsifiable.

A custom predicate is unavoidable here, because the attestation the workflows already produce does not carry
the facts this gate needs. GitHub's SLSA v1 provenance populates
`buildDefinition.internalParameters.github` with `event_name`, `repository_id`, `repository_owner_id`, and
`runner_environment` — repository and workflow identifiers only. **There is no `github.actor` or
`github.triggering_actor` anywhere in the predicate**, so neither the deploying human's identity nor any
review state can be read out of the existing provenance.

**Enforce the fact.** The two inputs need different mechanisms, and the asymmetry between them is now
established rather than open:

* **The image side is solved in principle.** Kyverno's `verifyImages` can verify an in-toto attestation
  with a keyless attestor pinned to the GitHub OIDC issuer and subject, and evaluate `conditions` against
  predicate fields with JMESPath — so approval count, base branch, and approvers-excluding-the-author are
  all expressible. Better still, a verified attestation can be **named**, which puts its values into the
  policy context for later rules and subsequent `apiCall` contexts. That is the mechanism by which
  `clusterpolicy-spicedb-authz.yaml` should obtain its subject identity: from a verified predicate rather
  than from `imageData.configData.config.Labels`, which anyone able to push to the registry path can set
  to anything.
* **The values artifact cannot be enforced this way, and it is not a matter of effort.** It is not a
  container image and never appears in a pod spec, so Kyverno has nothing to inspect. Flux's
  `OCIRepository.spec.verify` with `provider: cosign` verifies **plain signatures** and supports
  `matchOIDCIdentity` (regular expressions against the Fulcio certificate's issuer and subject), but it has
  no code path for in-toto or SLSA attestations and cannot evaluate predicate fields at all. Note also
  that `actions/attest-build-provenance` produces an attestation rather than a plain signature, so what the
  workflows push today would not satisfy `verify` even for signature checking — a `cosign sign` step is a
  prerequisite.

  So the ceiling on the values artifact is: *this artifact was signed by the identity of our publish
  workflow*. Strong provenance of origin, no evaluation of approval state. Carrying approval facts through
  to enforcement therefore requires either encoding them where admission can re-verify them against the
  rendered `Deployment` (the ADR-0001 shape, and the reason spike 4 exists), or accepting publication-side
  gating as tier 2's ceiling. **Deciding between those two is what remains of this spike's open risk.**

**Check the independence claim honestly.** An automated gate is inherently not the author, but it is only
*independent* if the author cannot influence it. That property is spike 2's subject, and this spike should
not claim four-eyes equivalence before spike 2 has an answer.

## Done when

You can state, per input and per tier, which mechanism carries the approval fact and which enforces it, with
a working demonstration that a `Deployment` is rejected when its image's approval predicate falls below the
required approval count or names the author among the approvers — plus a written position on the values
artifact asymmetry, including the option of declaring tier 2 structurally unable to enforce it.

## Notes

The repository already produces signed SLSA provenance for both artifacts, with `push-to-registry: true`,
and nothing consumes it — neither `OCIRepository` carries a `verify:` block, and no policy uses
`verifyImages`. The signing infrastructure and workflow permissions (`id-token: write`,
`attestations: write`) are therefore already in place; only the verification side is missing.

Consuming that existing provenance is now known-viable work rather than an investigation, and it should
land before this spike starts — see **Known-viable work that precedes the spikes** in the
[index](README.md). It is worth doing on its own merits: it closes the arbitrary-image substitution path
independently of whether the approval gate is ever built, and it gives this spike a working
`verifyImages` rule to extend rather than a blank file.
