# Tier 4 — Full governance and supply-chain verification

This is the final tier and matches the complete showcase: the platform/app split (tier 1), OCI-published
app values (tier 2), and SpiceDB ReBAC authorization (tier 3), now layered with opt-in governance
scoping, image-provenance verification, and a Policy Reporter dashboard.

## What this tier demonstrates

* **Opt-in governance scoping**: Kyverno policies only apply to namespaces labelled
  `governance.platform.io/managed: "true"` (see `clusters/kind/namespace-apps.yaml`), rather than being
  hardcoded to a single namespace as in tier 3. This is what makes governance policies reusable across
  an arbitrary number of application workspaces.
* **Two-layered image revision integrity**:
  1. [`clusters/kind/clusterpolicy-disallow-manual-image-revision.yaml`](clusters/kind/clusterpolicy-disallow-manual-image-revision.yaml) —
     blocks developers and incoming Helm charts from forging the `example.com/image-revision`
     annotation on `Deployment` templates.
  2. [`charts/archetype-backend/templates/policy.yaml`](charts/archetype-backend/templates/policy.yaml) —
     a namespaced Kyverno `Policy` packaged with the archetype chart itself. At admission time it queries
     the OCI registry for the container image configuration, extracts
     `org.opencontainers.image.revision`, and injects it into `spec.template.metadata.annotations`.
* **Image base ancestor & layer verification**
  ([`clusters/kind/clusterpolicy-verify-image-nginx-ancestor.yaml`](clusters/kind/clusterpolicy-verify-image-nginx-ancestor.yaml)):
  inspects the container image filesystem configuration at admission time using Kyverno's
  `imageRegistry` context, iterating across root filesystem layer hashes
  (`imageData.configData.rootfs.diff_ids`) to cryptographically assert that the image is derived from an
  approved `nginx:1.27` base image (`apps-source/Dockerfile`), regardless of intermediate build steps.
* **SpiceDB ReBAC, now label-scoped**: the admission gate introduced in tier 3
  (`clusterpolicy-spicedb-authz.yaml`) is retrofitted to match on the same
  `governance.platform.io/managed` label instead of a hardcoded `apps` namespace, consistent with the
  other policies in this tier.
* **Policy Reporter** (`kind-cluster/policy-reporter.tf`): a Flux-managed `HelmRelease` that persists
  policy execution history and violation reports in an embedded SQLite database backed by a persistent
  volume (`policy-reporter-sqlite-pvc`), giving governance decisions a queryable audit trail and web
  dashboard.

## Still no check on the change itself — and what would actually close it

Even at full governance, this tier doesn't add the control that's actually missing: an independent
check on the values change before it's published (see tier 2 for why that doesn't have to mean human
review). The two image-integrity policies here check **provenance of the image** — that its base
layers descend from an approved `nginx:1.27`, and that its `image-revision` annotation genuinely
matches the OCI config — not the *content* of the values artifact a deployer publishes. SpiceDB
(tier 3) strengthens deploy-time authorization and logging; these policies strengthen build-time
provenance (a documented, verifiable trail of how an artifact was built and from what). None of them
check whether the change was reviewed, tested against policy, or covered by a rollback plan before it
shipped, because no fact like that exists anywhere in this pipeline for Kyverno — the *admission
controller* running these checks, meaning it inspects an object and can allow, block, or modify it
right before Kubernetes accepts it — to verify.

A real closing mechanism has to produce that fact first, then enforce it — the same two-step pattern
this tier already uses for build provenance, and it works the same way regardless of which mitigation
from tier 2 you actually adopt:

1. **Produce a verifiable attestation that the chosen check passed.** An *attestation* is a signed,
   tamper-evident statement about an artifact — the same concept `clusterpolicy-verify-image-nginx-ancestor.yaml`
   already relies on for build provenance ("this image was built by this CI run from this source"),
   just applied to a different claim. Whether the check you adopted from tier 2 is an automated
   policy-as-code gate, a canary/rollback health check, or a human-reviewed PR, have that step sign a
   custom attestation (using a tool like `cosign attest`, or GitHub's build provenance mechanism with a
   custom predicate) — e.g. "passed policy gate `<name>` in run `<url>`" — and attach it to the
   published OCI artifact.
2. **Enforce it at admission.** Extend a `ClusterPolicy` here to use Kyverno's `verifyImages` feature
   (which checks that a required attestation exists and is validly signed before letting the image
   through) for that specific attestation type, the same way [`clusterpolicy-verify-image-nginx-ancestor.yaml`](clusters/kind/clusterpolicy-verify-image-nginx-ancestor.yaml)
   already verifies SLSA build provenance — reject the Deployment if the attestation is missing or
   doesn't verify.

Kyverno can only enforce facts that were actually produced and signed somewhere upstream; it can't
retroactively supply a check that never happened, automated or human. This repo doesn't implement
either step — picking a check (from tier 2's options) and wiring this attestation loop around it is
the natural next tier if you're adapting this pattern for real use.

## Directory layout

* [`kind-cluster/`](kind-cluster/): OpenTofu configuration that creates the kind cluster (named
  `tier-4`) and bootstraps `flux-operator`, Kyverno, and Policy Reporter.
* [`charts/`](charts/): Platform-owned Helm chart, including the chart-packaged image-revision policy.
* [`clusters/kind/`](clusters/kind/): Flux manifests — `OCIRepository`, `ArtifactGenerator`,
  `HelmRelease`, SpiceDB resources, and all governance `ClusterPolicy` objects.
* [`apps-source/`](apps-source/): Simulated application repository (container build files and
  `values.yaml`).
* [`fixtures/spicedb/`](fixtures/spicedb/): Human-readable SpiceDB schema (`schema.zed`) and
  relationship tuples (`relationships.txt`).
* [`scripts/`](scripts/): `spicedb-fixture.sh` for testing permissions and updating fixtures.

## Getting started

### Prerequisites

```sh
cd tier-4
mise install
```

This installs `kind`, `opentofu`, `helm`, `kubectl`, `yq`, and `flux`.

### Cluster lifecycle

```sh
cd tier-4/kind-cluster
./cluster.sh up      # Create the kind cluster, bootstrap Flux, Kyverno and Policy Reporter, and verify health
./cluster.sh check   # Check pod readiness and print component status
./cluster.sh down    # Destroy the OpenTofu stack and delete the kind cluster
```

> **Note**: Both `up` and `check` automatically configure `KUBECONFIG` from the OpenTofu state. You do
> not need to export `KUBECONFIG` manually.

---

## Application delivery workflow

Same as tier 2/3: the application team delivers updates independently of the platform GitOps repository
by publishing OCI artifacts. See the repository root [`.github/workflows/`](../.github/workflows/) for
`publish-chart.yaml`, `build-app-image.yaml`, and `publish-app-values.yaml`.

### Releasing an application update (runbook)

1. **Merge changes** to the main application branch.
2. **Trigger `Build app image`**: Navigate to **Actions** > **Build app image** and run the workflow on
   your target commit.
3. **Trigger `Bump archetype-backend values`**: Run the workflow with the `image_tag` input set to the
   commit SHA built in step 2.
4. **Verify deployment**:

   ```sh
   kubectl get helmrelease -n flux-system archetype-backend-demo
   kubectl get pods -n apps -l app.kubernetes.io/instance=archetype-backend-demo
   kubectl get deploy -n apps apps-archetype-backend-demo \
     -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
   ```

To verify that the verified image revision was stamped on the running workload:

```sh
kubectl get deploy -n apps apps-archetype-backend-demo \
  -o jsonpath='{.spec.template.metadata.annotations}'
```

### Policy Reporter dashboard

```sh
kubectl port-forward -n policy-reporter svc/policy-reporter-ui 8080:8080
```

Open `http://localhost:8080` in your browser to view real-time Kyverno policy reports, audit logs, and
compliance metrics.

### SpiceDB ReBAC authorization

```sh
# Port-forward SpiceDB HTTP API
kubectl port-forward -n authz svc/spicedb 8443:8443

# Check if user 'magnusp' has deploy permission
./scripts/spicedb-fixture.sh check magnusp

# Check an unauthorized user
./scripts/spicedb-fixture.sh check unauthorized-dev

# Edit fixtures/spicedb/relationships.txt or schema.zed, then apply:
./scripts/spicedb-fixture.sh apply
```

---

## Attestation & provenance verification

All published OCI artifacts (charts, images, and values) include GitHub Actions build provenance
attestations.

```sh
# Verify platform Helm chart
gh attestation verify oci://ghcr.io/magnusp/charts/<chart-name>:<version> --owner magnusp

# Verify application container image
gh attestation verify oci://ghcr.io/magnusp/apps/archetype-backend:<commit-sha> --owner magnusp

# Verify application values artifact
gh attestation verify oci://ghcr.io/magnusp/apps/archetype-backend-values:latest --owner magnusp
```

---

## Bare-metal & alternative delivery options

While this repository demonstrates GitHub Actions with GitHub OIDC, the same Kyverno and Flux
architecture adapts directly to **bare-metal / on-premises clusters** using modern identity providers
(Entra ID, Google Workspace, GitHub, Okta, Keycloak) without requiring cloud-hosted Kubernetes
(EKS/GKE/AKS) or cloud KMS:

| Pattern | Signing & identity mechanism | Kyverno verification mechanism |
| :--- | :--- | :--- |
| **Developer workstation CLI** | Cosign with corporate OIDC (Microsoft Entra ID, Google Workspace, GitHub) + public Sigstore Rekor | `verifyImages` keyless rule matching corporate issuer (e.g. `login.microsoftonline.com`, `accounts.google.com`) and user email regex. |
| **Self-hosted CI runners** | Bare-metal runners (GitLab CI, Jenkins, Drone) signing via HashiCorp Vault Transit Engine or local Cosign keys | `verifyImages` rule checking static public keys stored in a Kubernetes `Secret` or fetched from on-prem Vault. |
| **ChatOps / webhooks** | Slack / Mattermost webhook → Flux `Receiver` carrying triggering user email | Kyverno `apiCall` querying in-cluster SpiceDB to verify if the user has `deploy` permissions on the service. |
| **Direct `kubectl` access** | Entra ID / Google / Keycloak OIDC kubeconfig | Kyverno validation evaluating `request.userInfo.username` against SpiceDB ReBAC; blocks direct production edits in favor of GitOps. |
| **Automated dependency bots** | Renovate / Dependabot with dedicated bot keypair | Public key verification + OpenVEX / in-toto vulnerability scan conditions. |

### Example: keyless Sigstore with Microsoft Entra ID / Google Workspace

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-corporate-oidc-attestations
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-developer-identity
      match:
        any:
          - resources:
              kinds: [Deployment]
              namespaceSelector:
                matchLabels:
                  governance.platform.io/managed: "true"
      verifyImages:
        - imageReferences: ["ghcr.io/magnusp/apps/*"]
          attestations:
            - type: "https://slsa.dev/provenance/v1"
              attestors:
                - entries:
                    - keyless:
                        # Microsoft Entra ID, Google Workspace, or GitHub
                        issuer: "https://login.microsoftonline.com/<tenant-id>/v2.0"
                        subjectRegExp: ".*@company.com"
                        rekor:
                          url: "https://rekor.sigstore.dev"
```

---

## This is the final tier

There is no tier 5. If you're arriving here from [`tier-3`](../tier-3/README.md), see the "What this
tier demonstrates" section above for the delta. For the overall progression, see
the root README's [Tiers](../README.md#tiers) section.
