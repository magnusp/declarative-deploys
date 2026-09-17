# Automated change gates attest inputs in CI; admission re-verifies consistency

From tier 2 onward, `ArtifactGenerator` composes the platform chart with the app-owned values into an
`ExternalArtifact` **in-cluster at reconcile time**, so the artifact that actually deploys never exists in
CI and no CI-issued attestation can cover it directly. For the automated change-approval gates that
replace tier 0/1's human four-eyes review, we decided that CI attests the **inputs** (the values payload and
the image), and Kyverno then verifies at admission that the admitted object is **consistent** with those
attested facts — generalising the pattern `clusterpolicy-disallow-manual-image-revision.yaml` already
demonstrates.

## Considered options

* **Render and gate the composition in CI**, publishing the rendered output. Gives a single attested object
  identical to what deploys, but abandons runtime composition — effectively regressing the tier-2 premise
  that publishing an artifact *is* the deploy.
* **Sign the `ExternalArtifact` in-cluster after composition.** Covers the real deployed object, but places
  the signing identity inside the blast radius it protects and makes the
  "author cannot alter the gate" requirement substantially harder to satisfy.

## Consequences

The gate's assurance is bounded by the **completeness of the admission-time consistency checks**, not by the
strength of the signature. Enumerating those checks is therefore load-bearing spike work rather than an
implementation detail: any input fact that admission fails to re-verify is a fact the gate does not actually
enforce.
