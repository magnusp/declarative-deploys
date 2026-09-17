# Spike 1: Provenance-chained four-eyes

* **Target tier:** tier 2 (publication), tiers 3 and 4 (admission)
* **Enforcement point:** the CI workflow at tier 2; the Kyverno admission webhook at tiers 3 and 4
* **Size:** L
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

**Enforce the fact — and expect the two inputs to need different mechanisms.** This is where the spike's real
risk sits, and it should be resolved early:

* **The image** is straightforward in principle. Kyverno's `verifyImages` with an `attestations` block can
  require a validly signed predicate and evaluate `conditions` against its fields (approval count at or
  above the threshold, approvers excluding the author, base branch equal to `main`). Confirm that
  `verifyImages` conditions can express the independence check, not just a count.
* **The values artifact is invisible to admission control.** It is not a container image and never appears
  in a pod spec, so Kyverno has nothing to inspect. Flux's `OCIRepository.spec.verify` can verify a cosign
  or notation *signature* on it, but signature verification alone does not evaluate predicate conditions —
  it proves the artifact was signed, not that two people approved the change it carries.

  Resolving that asymmetry is the core of this spike. Candidate directions, in rough order of expected
  viability: verify the signature at the Flux layer and re-verify the approval facts at admission against the
  rendered `Deployment` (the ADR-0001 shape, and the reason spike 4 exists); gate the values artifact
  entirely on the publication side at tier 2 and accept that as the tier's ceiling; or validate the composed
  `ExternalArtifact` with a dedicated admission policy, which is the most complete option and the one with
  the worst gate-integrity story.

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
`verifyImages`. Whatever this spike concludes, the verification side needs building from scratch, but the
signing infrastructure and workflow permissions (`id-token: write`, `attestations: write`) are already in
place.
