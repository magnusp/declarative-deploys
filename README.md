# Declarative Deploys Showcase

A demonstration of decoupled platform engineering and application development workflows using Flux CD, OCI artifacts, and Kyverno on a local kind cluster.

## Overview

This repository demonstrates a separation of concerns between **platform teams** and **application teams**:

*   **Platform Engineering**: Owns archetype Helm charts (`charts/`) and cluster-wide governance policies. Charts are packaged and published to GitHub Container Registry (GHCR) with SemVer tags.
*   **Application Development**: Owns application source code and deployment parameters (`apps-source/values.yaml`). Application teams deploy by publishing container images and `values.yaml` artifacts to GHCR using a mutable `latest` tag without making Git commits to the cluster repository.
*   **Cluster Infrastructure**: Provisions a local kind cluster and bootstraps Flux CD and Kyverno using OpenTofu (`kind-cluster/`).
*   **Reconciliation & Composition**: Flux `source-watcher` composes the platform base chart and developer values into an `ExternalArtifact`, triggering immediate event-driven upgrades in `helm-controller` (`clusters/kind/`).

```
┌────────────────────────────────────────────────────────┐
│ Platform Concern                                       │
│ Base Chart (GHCR: oci://.../archetype-backend:0.1.1)   │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ Flux Artifact Composition (source-watcher)             │
│ ArtifactGenerator ───► ExternalArtifact (Merged Chart) │
└──────────────────────────▲─────────────────────────────┘
                           │
┌──────────────────────────┴─────────────────────────────┐
│ Developer Concern                                      │
│ App Values (GHCR: oci://.../values:latest)             │
└────────────────────────────────────────────────────────┘
```

---

## Directory Structure

*   [`kind-cluster/`](kind-cluster/): OpenTofu configuration that creates the kind cluster and installs the `flux-operator` and Kyverno.
*   [`charts/`](charts/): Platform-owned Helm charts consumed by application teams.
*   [`clusters/kind/`](clusters/kind/): Flux manifests defining the continuous delivery pipeline: `OCIRepository`, `ArtifactGenerator`, `HelmRelease`, and governance policies.
*   [`apps-source/`](apps-source/): Simulated application repository containing the container build files and environment values (`values.yaml`).
*   [`fixtures/spicedb/`](fixtures/spicedb/): Human-readable SpiceDB schema (`schema.zed`) and relationship tuples (`relationships.txt`).
*   [`scripts/`](scripts/): Developer CLI utilities, including `spicedb-fixture.sh` for testing permissions and updating fixtures.
*   [`.github/workflows/`](.github/workflows/): GitHub Actions workflows for publishing charts, images, and values artifacts with build provenance attestations.

---

## Getting Started

### Prerequisites

Ensure you have installed the required CLI tools managed by `mise`:

```sh
mise install
```

This installs:
*   `kind`
*   `opentofu`
*   `helm`
*   `kubectl`
*   `yq`
*   `flux`

### Cluster Lifecycle

All cluster lifecycle commands are managed by [`kind-cluster/cluster.sh`](kind-cluster/cluster.sh):

```sh
cd kind-cluster

./cluster.sh up      # Create the kind cluster, bootstrap Flux and Kyverno, and verify health
./cluster.sh check   # Check pod readiness and print component status
./cluster.sh down    # Destroy the OpenTofu stack and delete the kind cluster
```

> **Note**: Both `up` and `check` automatically configure `KUBECONFIG` from the OpenTofu state. You do not need to export `KUBECONFIG` manually.

---

## Application Delivery Workflow

The application team delivers updates independently of the platform GitOps repository.

### Workflows

1.  **Publish Helm chart** (`.github/workflows/publish-chart.yaml`):
    *   Packages the platform chart (`charts/archetype-backend`) with a given SemVer version.
    *   Pushes `oci://ghcr.io/magnusp/charts/archetype-backend:<version>`.
    *   Generates a GitHub build provenance attestation.
2.  **Build app image** (`.github/workflows/build-app-image.yaml`):
    *   Builds the container image from `apps-source/`.
    *   Pushes `ghcr.io/magnusp/apps/archetype-backend:<commit-sha>`.
    *   Stamps the OCI config labels `org.opencontainers.image.revision`, `org.opencontainers.image.vendor`, and `dev.authz.app.deployer`.
    *   Generates a GitHub build provenance attestation.
3.  **Bump archetype-backend values** (`.github/workflows/publish-app-values.yaml`):
    *   Updates `image.tag` in `apps-source/values.yaml` to the target commit SHA.
    *   Pushes `apps-source/` as an OCI artifact to `ghcr.io/magnusp/apps/archetype-backend-values:latest` with deployer provenance annotations.
    *   Generates a GitHub build provenance attestation.

### Releasing an Application Update (Runbook)

Follow these steps to deploy an application change:

1.  **Merge changes** to the main application branch.
2.  **Trigger `Build app image`**:
    *   Navigate to **Actions** > **Build app image** and run the workflow on your target commit.
3.  **Trigger `Bump archetype-backend values`**:
    *   Run the workflow with the `image_tag` input set to the commit SHA built in Step 2.
4.  **Verify Deployment**:
    *   Flux automatically detects the new values artifact digest, generates a new `ExternalArtifact`, and reconciles the `HelmRelease`:

    ```sh
    kubectl get helmrelease -n flux-system archetype-backend-demo
    kubectl get pods -n apps -l app.kubernetes.io/instance=archetype-backend-demo
    kubectl get deploy -n apps apps-archetype-backend-demo \
      -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
    ```

---

## Platform Governance & Kyverno Policies

This repository separates policy enforcement into two layers and scopes governance policies to opt-in application workspaces labeled `governance.platform.io/managed: "true"` (e.g. `namespace/apps`):

1.  **Platform Validation Policy** ([`clusters/kind/clusterpolicy-disallow-manual-image-revision.yaml`](clusters/kind/clusterpolicy-disallow-manual-image-revision.yaml)):
    *   Enforces across managed workspaces that developers and incoming Helm charts cannot manually set or forge the `example.com/image-revision` annotation on `Deployment` templates.
2.  **Archetype Mutation Policy** ([`charts/archetype-backend/templates/policy.yaml`](charts/archetype-backend/templates/policy.yaml)):
    *   A namespaced Kyverno `Policy` packaged with the archetype chart.
    *   At admission time, it queries the OCI registry for the container image configuration, extracts `org.opencontainers.image.revision`, and injects it into `spec.template.metadata.annotations`.
3.  **Image Provenance & Nginx Base Ancestor Policy** ([`clusters/kind/clusterpolicy-verify-image-nginx-ancestor.yaml`](clusters/kind/clusterpolicy-verify-image-nginx-ancestor.yaml)):
    *   Uses Kyverno's `verifyImages` rule to verify the cryptographic SLSA v1 build provenance attestation emitted by GitHub Actions via Sigstore Rekor.
    *   Enforces that the application container image is authentically built from this repository's workflows and explicitly anchored in an approved `nginx` base image dependency (`apps-source/Dockerfile`).

To verify that the verified image revision was stamped on the running workload:

```sh
kubectl get deploy -n apps apps-archetype-backend-demo \
  -o jsonpath='{.spec.template.metadata.annotations}'
```

### Policy Reporter & Dashboard

Policy Reporter is installed as a Flux `HelmRelease` (`kind-cluster/policy-reporter.tf`) and persists policy execution history and violation reports in an embedded SQLite database backed by a persistent volume (`policy-reporter-sqlite-pvc`).

To access the interactive Policy Reporter web dashboard:

```sh
kubectl port-forward -n policy-reporter svc/policy-reporter-ui 8080:8080
```

Open `http://localhost:8080` in your browser to view real-time Kyverno policy reports, audit logs, and compliance metrics.

### SpiceDB ReBAC Authorization

The cluster includes an ephemeral SpiceDB instance managed by the **SpiceDB Operator** (`clusters/kind/spicedb-operator.yaml` & `clusters/kind/spicedb-cluster.yaml`) and an admission gate policy ([`clusters/kind/clusterpolicy-spicedb-authz.yaml`](clusters/kind/clusterpolicy-spicedb-authz.yaml)):

1.  **OCI Deployer Metadata**: When workflows build container images and package values artifacts, they embed the triggering actor (`dev.authz.app.deployer`) in the OCI labels.
2.  **Admission Gate Check**: When Flux reconciles a deployment, Kyverno extracts the deployer identity and queries SpiceDB's `/v1/permissions/check` API to verify if the actor has `deploy` permissions on the service.
3.  **Human-Readable Fixtures (`fixtures/spicedb/`)**:
    *   [`fixtures/spicedb/schema.zed`](fixtures/spicedb/schema.zed): Standard SpiceDB schema definition using `.zed` syntax.
    *   [`fixtures/spicedb/relationships.txt`](fixtures/spicedb/relationships.txt): Line-delimited relationship tuples (`resource#relation@subject`).
4.  **Experimenting & Testing Permissions**:

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

## Attestation & Provenance Verification

All published OCI artifacts (charts, images, and values) include GitHub Actions build provenance attestations.

To verify that an artifact was produced by an authentic repository workflow using the GitHub CLI:

```sh
# Verify platform Helm chart
gh attestation verify oci://ghcr.io/magnusp/charts/<chart-name>:<version> --owner magnusp

# Verify application container image
gh attestation verify oci://ghcr.io/magnusp/apps/archetype-backend:<commit-sha> --owner magnusp

# Verify application values artifact
gh attestation verify oci://ghcr.io/magnusp/apps/archetype-backend-values:latest --owner magnusp
```
