# Automated change gates attest inputs in CI; admission re-verifies consistency

From tier 2 onward, `ArtifactGenerator` composes the platform chart with the app-owned values into an
`ExternalArtifact` inside the cluster, at reconcile time. The artifact that deploys therefore never exists
in continuous integration (CI), and no CI-issued attestation can cover it directly.

For the automated change-approval gates that replace the human four-eyes review of tiers 0 and 1, CI
attests the **inputs**: the values payload and the image. Kyverno then verifies at admission that the
admitted object is **consistent** with those attested inputs. This generalizes the pattern that
`clusterpolicy-disallow-manual-image-revision.yaml` already applies to a single annotation.

## Considered options

* **Render and gate the composition in CI**, then publish the rendered output. This produces one attested
  object identical to what deploys. It also abandons runtime composition, which regresses the tier 2
  premise that publishing an artifact is the deploy.
* **Sign the `ExternalArtifact` in the cluster after composition.** This covers the object that actually
  deploys. It also places the signing identity inside the system it protects, which makes gate integrity
  much harder to establish.

## Consequences

The **completeness of the admission-time consistency checks** bounds the gate's assurance, not the strength
of the signature. Enumerating those checks is therefore spike work rather than an implementation detail. Any
input fact that admission fails to re-verify is a fact the gate does not enforce.
