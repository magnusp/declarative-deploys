# Architecture Evolution & Decision Timeline

This document records the chronological development, architectural trade-offs, and operational decisions made in the `declarative-deploys` showcase.

---

## Timeline of Decisions & Pull Requests

### Phase 1: Initial Bootstrap & GitOps Foundation

*   **[PR #1](https://github.com/magnusp/declarative-deploys/pull/1)**: *Drop Flux pull secrets now that all repos are public*
    *   **Context**: All charts and repositories were made publicly accessible.
    *   **Decision**: Removed local pull secret requirements in cluster manifests, simplifying initial bootstrap.
*   **[PR #2](https://github.com/magnusp/declarative-deploys/pull/2)**: *Add simulated app repo and values-based deployment workflow*
    *   **Context**: Establishing the boundary between platform engineering (Helm charts) and application developers (`values.yaml`).
    *   **Decision**: Introduced `apps-source/` with independent GitHub Actions workflows to publish container images (`build-app-image.yaml`) and values artifacts (`publish-app-values.yaml`).
*   **[PR #3](https://github.com/magnusp/declarative-deploys/pull/3)**: *Fix HelmRelease dependsOn referencing a Kustomization*
    *   **Context**: `HelmRelease.spec.dependsOn` rejected references to `Kustomization` resources.
    *   **Decision**: Removed the invalid `dependsOn`. The `HelmRelease` failed and retried until the values ConfigMap materialized.
*   **[PR #4](https://github.com/magnusp/declarative-deploys/pull/4)** & **[PR #5](https://github.com/magnusp/declarative-deploys/pull/5)**: *Fix invalid label when chart installed via OCIRepository chartRef & Bump to 0.1.1*
    *   **Context**: Helm appends build metadata to chart versions (e.g. `0.1.0+digest`), but `+` is an illegal Kubernetes label character.
    *   **Decision**: Sanitized the label in `_helpers.tpl` using `replace "+" "_"` and released chart version `0.1.1`.
*   **[PR #6](https://github.com/magnusp/declarative-deploys/pull/6)**: *Document app team's release runbook in README*
    *   **Context**: Documented the step-by-step developer release process.

---

### Phase 2: Platform Policy & Governance

*   **[PR #7](https://github.com/magnusp/declarative-deploys/pull/7)**: *Install Kyverno via HelmRelease, add test image-revision mutation policy*
    *   **Context**: Verifying supply-chain provenance on workloads without requiring developers to manually maintain commit annotations.
    *   **Decision**: Installed Kyverno via Flux and created a `ClusterPolicy` to read `org.opencontainers.image.revision` off container image configs in GHCR and mutate the `Deployment` pod template.
    *   **Identified Limitations**:
        1.  `helm-controller` did not watch `valuesFrom` ConfigMaps, requiring an aggressive `10s` polling interval workaround.
        2.  `retries: -1` was added to prevent Helm from stalling permanently on bad image tags.

---

### Phase 3: Artifact Composition & Decoupled Delivery

*   **[PR #8](https://github.com/magnusp/declarative-deploys/pull/8)**: *Migrate to Flux ArtifactGenerator and ExternalArtifact*
    *   **Problem**: Materializing developer values into in-cluster ConfigMaps caused reconciliation lag, race conditions, and heavy polling loops.
    *   **Solution**:
        *   Enabled `source-watcher` in `FluxInstance` (upgraded Flux to `2.7.5` and operator to `0.58.1`).
        *   Created `ArtifactGenerator/archetype-backend-demo` to deep-merge the platform base chart and developer values into an `ExternalArtifact`.
        *   Pointed `HelmRelease.spec.chartRef` directly to the `ExternalArtifact`.
        *   Removed `apps-source/kustomization.yaml` and `clusters/kind/kustomization-archetype-backend-values.yaml`.
    *   **Result**: Zero polling lag and native event-driven upgrades whenever either the chart or values artifact updates in GHCR.
*   **[PR #11](https://github.com/magnusp/declarative-deploys/pull/11)**: *Remove cert-manager*
    *   **Context**: Evaluated cluster dependencies. The showcase workloads only use `Deployment` and `Service` without ingress or certificates.
    *   **Decision**: Removed `cert-manager` from OpenTofu, Flux, and cluster health checks, speeding up cluster standup time to under 90 seconds.

---

### Phase 4: Policy Modularization & Remediation Hardening

*   **[PR #12](https://github.com/magnusp/declarative-deploys/pull/12)**: *Package Kyverno policy into archetype-backend Helm chart & split platform governance*
    *   **Problem**: Hardcoding workload names in static cluster policies prevented multi-workload reuse and lacked anti-tamper validation.
    *   **Solution**:
        1.  **Archetype Mutation Policy** (`charts/archetype-backend/templates/policy.yaml`): Packaged a namespaced Kyverno `Policy` inside the chart that dynamically references `{{ include "archetype-backend.name" . }}` and mutates the pod template with verified OCI metadata.
        2.  **Platform Validation Policy** (`clusters/kind/clusterpolicy-disallow-manual-image-revision.yaml`): A cluster-wide policy that blocks developers from manually forging or setting `example.com/image-revision`.
*   **[PR #13](https://github.com/magnusp/declarative-deploys/pull/13)**: *Update remediation strategy to automated rollback and bump OCIRepository to v1*
    *   **Context**: With `ExternalArtifact` in place, `retries: -1` was no longer necessary.
    *   **Decision**:
        *   Configured bounded retries (`3`) with automated rollback (`strategy: rollback`, `remediateLastFailure: true`).
        *   Upgraded all `OCIRepository` manifests from deprecated `v1beta2` to `source.toolkit.fluxcd.io/v1`.
*   **[PR #14](https://github.com/magnusp/declarative-deploys/pull/14)**: *Update README to align with Google documentation style guide*
    *   **Context**: Cleaned up documentation, added architecture diagrams, and aligned with standard technical writing guidelines.
*   **[PR #16](https://github.com/magnusp/declarative-deploys/pull/16)**: *Add Policy Reporter with persistent SQLite storage and Web UI*
    *   **Context**: Needed persistent storage for Kyverno policy execution events, audit logs, and graphical reports.
    *   **Decision**: Installed Policy Reporter via Flux `HelmRelease` from `https://kyverno.github.io/policy-reporter`, configured with a `PersistentVolumeClaim` backed by kind's `local-path` provisioner for embedded SQLite event persistence and enabled the Policy Reporter UI.

---

### Phase 5: Zero-Trust Delivery & SpiceDB ReBAC Authorization

*   **[PR #17](https://github.com/magnusp/declarative-deploys/pull/17)**: *Add SpiceDB operator, in-cluster ephemeral ReBAC authorization, human-readable fixtures, and dedicated apps workspace*
    *   **Problem**: In GitOps, cluster controllers execute deployments using generic machine identities, making it difficult to enforce who originally authored or triggered the release without granting engineers direct cluster access. Additionally, global Kyverno cluster policies must not interfere with third-party or infrastructure controllers.
    *   **Solution**:
        1.  **OCI Deployer Attestation & Metadata**: Workflows (`build-app-image.yaml` and `publish-app-values.yaml`) stamp the triggering GitHub actor (`dev.authz.app.deployer`) into the OCI artifact labels.
        2.  **Dedicated Opt-In Apps Workspace**: Created `namespace/apps` labeled with `governance.platform.io/managed: "true"` and scoped all Kyverno validation and ReBAC cluster policies with `namespaceSelector` to safely confine policy evaluation to application workloads.
        3.  **SpiceDB Operator via Flux**: Installed `authzed/spicedb-operator` using Flux `GitRepository` + `Kustomization` with explicit RBAC extensions (`spicedb-operator-rbac.yaml`).
        4.  **In-Cluster Ephemeral SpiceDB & Human-Readable Fixtures**: Deployed a `SpiceDBCluster` resource in namespace `authz` and an automated initialization `Job` that seeds schema (`schema.zed`) and relationship tuples (`relationships.txt`) from a ConfigMap.
        5.  **Kyverno Admission Policy**: Added `ClusterPolicy/spicedb-attested-deploy-authz` querying SpiceDB's `/v1/permissions/check` API to assert that the actor has `deploy` permissions before admitting the workload.
        6.  **Cryptographic Base Image Lineage Policy**: Added `ClusterPolicy/verify-app-image-nginx-ancestor` using Kyverno's `verifyImages` to cryptographically verify GitHub SLSA v1 build provenance and enforce that deployed application containers are derived from an approved `nginx` base image.

---

## Architectural Decision Summary Matrix

| Decision Area | Previous Approach | Final Approach | Rationale |
| :--- | :--- | :--- | :--- |
| **Values Materialization** | Kustomize `ConfigMapGenerator` $\rightarrow$ `ConfigMap` | `ArtifactGenerator` $\rightarrow$ `ExternalArtifact` | Eliminates intermediate cluster objects and provides instant, event-driven reconciliation. |
| **Helm Polling Interval** | `10s` (tight loop workaround) | `10m` | Updates are triggered immediately by `ExternalArtifact` revision events. |
| **Failure Remediation** | `retries: -1` (unbounded) | `retries: 3` + `rollback` | Automatically rolls back to the last stable release on failure; recovers automatically on next valid publish. |
| **Policy Scope** | Single static `ClusterPolicy` in GitOps | Split: Platform Validation (`ClusterPolicy`) + Chart Mutation (`Policy`) | Guarantees tamper-resistance while making archetype charts self-contained. |
| **Policy Reporting** | None (in-memory reports only) | Policy Reporter + Persistent SQLite (PVC) + Web UI | Persists policy reports and audit logs locally with zero external database dependencies. |
| **Deployment Authorization** | Kubernetes RBAC on Flux machine account | Provenance Deployer Identity + SpiceDB ReBAC check | Enforces decentralized zero-trust access control without giving developers cluster credentials. |
| **Base Image Lineage** | Unverified container base layers | Kyverno `verifyImages` with SLSA v1 Attestation | Cryptographically guarantees that all admitted workloads derive from trusted golden base images. |
| **In-Cluster TLS** | `cert-manager` installed via Flux | Removed | Reduced cluster surface area and cut standup time in half. |
