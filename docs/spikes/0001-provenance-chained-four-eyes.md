# Spike 1: Provenance-chained four-eyes

* **Target tier:** tier 2 (publication), tiers 3 and 4 (admission)
* **Enforcement point:** the CI workflow at tier 2; the Kyverno admission webhook at tiers 3 and 4
* **Size:** M
* **Controls:**
  * A.8.32 — change management
  * A.8.25 — secure development lifecycle
  * A.8.4 — access to source code
  * A.5.3 — segregation of duties

## Question

Can you prove automatically, at deploy time, that everything reaching the cluster descends from a commit
that passed a pull request with the required number of independent approvals, and reject the deploy when it
does not?

If this works, tiers 2 through 4 do not substitute a new control for four-eyes review. They carry the
existing control forward, machine-verified, into a delivery model that has no pull request of its own.

## Why the gap exists

Tier 2 separates delivery from git. The application team publishes
`ghcr.io/magnusp/apps/archetype-backend:<sha>` and
`ghcr.io/magnusp/apps/archetype-backend-values:latest`, and Flux deploys whatever appears there. The commit
SHA in the image tag suggests provenance, but nothing verifies it, and nothing records whether anyone
reviewed that commit.

The values artifact is further removed. `publish-app-values.yaml` rewrites `image.tag` using
`yq -i '.image.tag = strenv(IMAGE_TAG)'` and never commits the result, taking `IMAGE_TAG` from a free-text
`workflow_dispatch` input. The reviewed file in the repository specifies `tag: "latest"`. The values
payload that deploys therefore has no reviewed counterpart. Reviewing `apps-source/values.yaml` reviews a
file that changes after approval and before publication.

## Investigation approach

### Produce the fact

At build and publish time, query the approval state of the commit being built. Call
`GET /repos/{owner}/{repo}/commits/{sha}/pulls`, then read the pull request's reviews. Emit a signed
attestation with a custom predicate, using either `actions/attest` with your own `predicate-type` or
`cosign attest`. This differs from the `actions/attest-build-provenance` step both workflows already run,
which produces SLSA provenance and says nothing about review.

The predicate needs the commit SHA, the pull request number, the approving reviewer identities, the
approval count, the base branch, and the commit author. A gate needs all of these to evaluate independence,
not only count. Record the branch protection or ruleset requirements in force at merge time as well,
because repository settings can be relaxed afterward. A predicate that asserts only "the rules were
satisfied" cannot be checked against anything.

A custom predicate is unavoidable, because the attestation the workflows produce today lacks the facts this
gate needs. GitHub's SLSA v1 provenance populates `buildDefinition.internalParameters.github` with
`event_name`, `repository_id`, `repository_owner_id`, and `runner_environment`. These identify the
repository and the workflow. **The predicate contains no `github.actor` or `github.triggering_actor`**, so
neither the deploying human's identity nor any review state can be read from the existing provenance.

### Enforce the fact

The two inputs need different mechanisms, and the difference between them is established rather than open.

* **The image side is solved in principle.** Kyverno's `verifyImages` verifies an in-toto attestation with
  a keyless attestor pinned to the GitHub OIDC issuer and subject, and evaluates `conditions` against
  predicate fields using JMESPath. Approval count, base branch, and approvers-excluding-the-author are all
  expressible. A verified attestation can also be **named**, which places its values in the policy context
  for later rules and for subsequent `apiCall` contexts. Use that mechanism to give
  `clusterpolicy-spicedb-authz.yaml` its subject identity from a verified predicate instead of from
  `imageData.configData.config.Labels`, which anyone able to push to the registry path can set to any
  value.
* **The values artifact cannot be enforced this way.** It is not a container image and never appears in a
  pod spec, so Kyverno has nothing to inspect. Flux's `OCIRepository.spec.verify` with `provider: cosign`
  verifies plain signatures and supports `matchOIDCIdentity`, which matches Go regular expressions against
  the Fulcio certificate's issuer and subject. It has no code path for in-toto or SLSA attestations and
  cannot evaluate predicate fields. `actions/attest-build-provenance` also produces an attestation rather
  than a plain signature, so what the workflows push today does not satisfy `verify` even for signature
  checking. A `cosign sign` step is a prerequisite.

The limit on the values artifact is therefore a single claim: the platform's publish workflow signed this
artifact. That is strong provenance of origin with no evaluation of approval state. Carrying approval facts
through to enforcement requires one of two choices. Either encode them where admission can re-verify them
against the rendered `Deployment`, which is the [architectural assumption](README.md#architectural-assumption)
all five spikes share and the reason [spike 4](0004-admission-consistency-reverification.md) exists. Or
accept publication-side gating as tier 2's limit. **Choosing between those two is the remaining open risk
in this spike.**

### Confirm the capability claims before scheduling

The Kyverno and Flux behavior described in this section comes from DeepWiki's analysis of the
`kyverno/kyverno` and `fluxcd/source-controller` repositories. It has not been checked against primary
documentation or a live cluster.

The load-bearing claim is that Kyverno names a verified attestation and exposes its predicate fields to
later rules and to subsequent `apiCall` contexts. This spike's size assumes that works as described, and
so does the approach [spike 4](0004-admission-consistency-reverification.md) takes to sourcing the SpiceDB
subject identity. Confirm it first. If the mechanism turns out narrower, this spike grows and spike 4
needs a different route for carrying verified facts into policy logic.

### Check the independence claim honestly

An automated gate is not the author, but it is independent only if the author cannot influence it.
[Spike 2](0002-gate-integrity.md) covers that property. Do not claim four-eyes equivalence before spike 2
has an answer.

## Done when

You can state, for each input and each tier, which mechanism carries the approval fact and which enforces
it. You have a working demonstration that admission rejects a `Deployment` when its image's approval
predicate falls below the required approval count or names the author among the approvers. You have a
written position on the values artifact, including the option of declaring tier 2 unable to enforce it.

## Notes

The repository already produces signed SLSA provenance for both artifacts with `push-to-registry: true`,
and nothing consumes it. The signing infrastructure and the workflow permissions (`id-token: write` and
`attestations: write`) are in place. Only the verification side is missing.

Consuming that existing provenance is known-viable work rather than an investigation, and it should
land before this spike starts. See the known-viable work section of the [index](README.md). It closes the
arbitrary-image substitution path whether or not the approval gate gets built, and it gives this spike a
working `verifyImages` rule to extend.
