# Declarative Deploys Showcase

A demonstration of decoupled platform engineering and application development workflows using Flux CD,
OCI artifacts, and Kyverno on a local kind cluster — presented as a progression of five isolated tiers,
each adding one capability on top of the last.

## Tiers

This repository demonstrates the platform/application split, GitOps delivery, and supply-chain
governance as a progression rather than a single finished state. Each tier is a fully isolated
directory — its own kind cluster, its own OpenTofu stack, its own manifests — that peels back
capability from the final tier (`tier-4`, which is the complete showcase). Read them in order; each
tier's `README.md` ends with a "Progressing to tier-(N+1)" section explaining exactly what changes and
why.

The throughline: Flux and a deployer tool already exist, but with no platform/app split (tier 0) →
separating platform and application ownership (tier 1) → decoupling application deploys from git
commits (tier 2) → authorizing who can deploy (tier 3) → verifying what gets deployed (tier 4).

| Tier | Name | Introduces |
| :--- | :--- | :--- |
| [tier-0](tier-0/README.md) | Flux + deployer tool | Raw manifests, git-committed by a deployer tool, Flux-reconciled — the real-world baseline. |
| [tier-1](tier-1/README.md) | Helm chart split | Platform-owned chart vs. app-owned values; the core platform/app lesson. |
| [tier-2](tier-2/README.md) | OCI-published values | App team deploys by publishing an OCI artifact, no git commit required. |
| [tier-3](tier-3/README.md) | SpiceDB ReBAC | Admission-time authorization: who is allowed to deploy. |
| [tier-4](tier-4/README.md) | Full governance | Opt-in policy scoping, image-revision integrity, base-image attestation, Policy Reporter. |

Start at `tier-0` and work upward, or jump straight to `tier-4` if you want the full, final architecture.

## Overview

At its most complete (`tier-4`), this repository demonstrates a separation of concerns between
**platform teams** and **application teams**:

* **Platform engineering**: owns archetype Helm charts (`tier-N/charts/`) and cluster-wide governance
  policies. Charts are packaged and published to GitHub Container Registry (GHCR) with SemVer tags.
* **Application development**: owns application source code and deployment parameters
  (`tier-N/apps-source/values.yaml`). From tier 2 onward, application teams deploy by publishing
  container images and `values.yaml` artifacts to GHCR using a mutable `latest` tag without making git
  commits to the cluster repository.
* **Cluster infrastructure**: each tier provisions its own local kind cluster and bootstraps whatever
  subset of Flux CD / Kyverno that tier needs, using OpenTofu (`tier-N/kind-cluster/`).
* **Reconciliation & composition** (tier 2+): Flux `source-watcher` composes the platform base chart and
  developer values into an `ExternalArtifact`, triggering immediate event-driven upgrades in
  `helm-controller` (`tier-N/clusters/kind/`).

```mermaid
flowchart TB
    chart["Platform concern<br/>Base chart (GHCR: oci://.../archetype-backend:0.1.1)"]
    values["Developer concern<br/>App values (GHCR: oci://.../values:latest)"]
    compose["Flux artifact composition (source-watcher)<br/>ArtifactGenerator → ExternalArtifact (merged chart)"]

    chart --> compose
    values --> compose
```

This diagram reflects tier 2 and above — see the [Tiers](#tiers) section above for what's present at
earlier tiers.

---

## Automated change approval

Decoupling deploys from git commits removes a control that is easy to overlook. At tiers 0 and 1 the
application team commits to git, so every change travels through a pull request, and someone other than
the author approves it before it merges. Four-eyes review is the control, and the git history is the
evidence. The delivery mechanism supplies both.

Tier 2 replaces the delivery mechanism, and the control disappears with it. Publishing an OCI artifact is
the deploy, so no pull request exists against the thing that deploys, and no one approves it. Tiers 3 and
4 add authorization, which answers whether the actor was allowed, and build provenance, which answers
where the artifact came from. Neither answers whether anyone examined the change before it shipped.

[`docs/spikes/`](docs/spikes/README.md) holds time-boxed investigation drafts into automated pre-exposure
gates that carry that approval forward without a human. They are framed against ISO/IEC 27001:2022 Annex
A, Clause 8. They describe proposed work rather than implemented capability: no tier enforces a
change-approval gate today.

---

## Directory structure

* [`tier-0/`](tier-0/) through [`tier-4/`](tier-4/): isolated tier directories, each with its own
  `kind-cluster/` (OpenTofu), application/chart/policy manifests, and `README.md` explainer. See
  [Tiers](#tiers) above.
* [`.github/workflows/`](.github/workflows/): GitHub Actions workflows for publishing charts, images,
  and values artifacts with build provenance attestations. Each workflow notes the tier it becomes
  relevant at.
* [`docs/spikes/`](docs/spikes/README.md): drafts of proposed investigations into automated change
  approval for tiers 2 through 4. See [Automated change approval](#automated-change-approval).

---

## Prerequisites

Each tier's tooling is version-pinned via `mise` (see that tier's `mise.toml` and
`kind-cluster/mise.toml`):

```sh
cd tier-N
mise install
```

## Cluster lifecycle

Every tier's cluster lifecycle is managed by its own `tier-N/kind-cluster/cluster.sh`:

```sh
cd tier-N/kind-cluster

./cluster.sh up      # Create the tier's kind cluster and bring up whatever that tier needs
./cluster.sh check   # Check readiness and print component status
./cluster.sh down    # Tear the tier's cluster down
```

> **Note**: `up` and `check` automatically configure `KUBECONFIG` from that tier's OpenTofu state. You
> do not need to export `KUBECONFIG` manually. Tiers use distinct kind cluster names (`tier-0` …
> `tier-4`), so multiple tiers could in principle run side by side.

For the deep-dive on any specific tier's application delivery workflow, governance policies,
attestation verification, or SpiceDB ReBAC setup, see that tier's own `README.md` — most of that detail
now lives in [`tier-4/README.md`](tier-4/README.md), since it's the tier where all of it is present.

CI workflows in [`.github/workflows/`](.github/workflows/) live at the repository root (a GitHub Actions
requirement) but are only meaningful once you've reached the tier that introduces them — each workflow
file notes the tier it becomes relevant at.
