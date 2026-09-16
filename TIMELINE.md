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

### Phase 6: Tiered Progression Restructure

*   **Scale down into a tiered showcase**: *Restructure into a tiered progression (tier-0 through tier-5)*
    *   **Problem**: The repository demonstrated its full final architecture (chart/app split, OCI artifact
        composition, SpiceDB ReBAC, two-layer Kyverno governance, Policy Reporter) as a single indivisible
        state. There was no way to learn or demo the platform/app split without also standing up every
        governance and authorization layer at once.
    *   **Solution**: Split the repository into six self-contained tiers (`tier-0` … `tier-5`), each with
        its own kind cluster, OpenTofu stack, and manifests, peeling back one capability at a time from
        the original final state (now `tier-5`, moved via `git mv` to preserve history):
        1.  **tier-0**: raw manifests, `kubectl apply`, no reconciler, no Helm.
        2.  **tier-1**: same raw manifests, now reconciled by Flux.
        3.  **tier-2**: introduces the platform/app split via a Helm chart (`chartRef` directly to the
            chart `OCIRepository`, inline values, no `ArtifactGenerator` yet).
        4.  **tier-3**: adds the app-published values OCI artifact and `ArtifactGenerator`/`ExternalArtifact`
            composition, decoupling app deploys from git commits.
        5.  **tier-4**: adds SpiceDB ReBAC, scoped directly to the `apps` namespace (no label opt-in yet).
        6.  **tier-5**: unchanged final state — retrofits the SpiceDB policy to the
            `governance.platform.io/managed` label scheme and adds both image-integrity `ClusterPolicy`
            objects plus Policy Reporter.
    *   **Decision**: CI workflows stay at the repository root (a GitHub Actions requirement) but are
        hardcoded to `tier-5/` paths, since only tier-5 has the full publishing pipeline; each workflow
        notes the tier it becomes relevant at. The root `README.md` absorbed the tier index (formerly a
        separate `TIERS.md`) as its "Tiers" section, so there is a single entry point into the repository.
*   **Collapse tier-0 into tier-1 to match a real baseline**: *Renumber to a five-tier progression
    (tier-0 through tier-4)*
    *   **Problem**: The six-tier progression above started from a "worst case" of raw, hand-applied
        manifests with no Flux at all. That doesn't match the environment this showcase is meant to
        prepare people for: Flux is already reconciling a cluster repository there, and a custom
        in-house deployer tool already automates getting manifests into it — triggered by a merge to an
        app repo's default branch, it optionally builds/tags a Docker image and optionally templates
        manifests and git-commits them into the Flux-managed repo. Starting from raw `kubectl apply`
        taught a lesson (GitOps reconciliation) that this audience has already internalized.
    *   **Solution**: Collapsed the old `tier-0` (raw manifests, hand-applied) and old `tier-1` (the
        same manifests, now Flux-reconciled) into a single new `tier-0` that starts from "Flux + a
        deployer tool already exist, but there's no platform/app split yet" — narrated entirely in
        `tier-0/README.md`; the deployer tool itself is described in prose, not implemented in the repo.
        Every subsequent tier renumbered down by one (old `tier-2`→`tier-1`, `tier-3`→`tier-2`,
        `tier-4`→`tier-3`, `tier-5`→`tier-4`), so the progression is now five tiers, not six, and the
        final governance tier lives at `tier-4/` instead of `tier-5/`.

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
| **Repository Structure** | Single flat directory tree at the final architecture | Six isolated `tier-N/` directories, each a complete standalone stack | Lets the platform/app split, GitOps, and governance concerns be learned and demoed incrementally instead of all at once. |
