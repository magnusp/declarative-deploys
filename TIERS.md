# Tiers

This repository demonstrates the platform/application split, GitOps delivery, and supply-chain
governance as a progression rather than a single finished state. Each tier is a fully isolated
directory — its own kind cluster, its own OpenTofu stack, its own manifests — that peels back
capability from the final tier (`tier-5`, which is the complete showcase). Read them in order; each
tier's `README.md` ends with a "Progressing to tier-(N+1)" section explaining exactly what changes and
why.

The throughline: no separation of concerns (tier 0) → automated reconciliation (tier 1) → separating
platform and application ownership (tier 2) → decoupling application deploys from git commits (tier 3)
→ authorizing who can deploy (tier 4) → verifying what gets deployed (tier 5).

| Tier | Name | Introduces |
| :--- | :--- | :--- |
| [tier-0](tier-0/README.md) | Raw manifests | `kubectl apply`, no reconciler, no Helm — the worst case. |
| [tier-1](tier-1/README.md) | Flux GitOps | Automated reconciliation of the same raw manifests. |
| [tier-2](tier-2/README.md) | Helm chart split | Platform-owned chart vs. app-owned values; the core platform/app lesson. |
| [tier-3](tier-3/README.md) | OCI-published values | App team deploys by publishing an OCI artifact, no git commit required. |
| [tier-4](tier-4/README.md) | SpiceDB ReBAC | Admission-time authorization: who is allowed to deploy. |
| [tier-5](tier-5/README.md) | Full governance | Opt-in policy scoping, image-revision integrity, base-image attestation, Policy Reporter. |

Each tier directory is self-contained (own `kind-cluster/` OpenTofu stack, own `cluster_name`), so you
can stand one up in isolation with `cd tier-N/kind-cluster && ./cluster.sh up`. See the root
[`README.md`](README.md) for prerequisites and the overall repository purpose.

CI workflows in [`.github/workflows/`](.github/workflows/) live at the repository root (a GitHub
Actions requirement) but are only meaningful once you've reached the tier that introduces them — each
workflow file notes the tier it becomes relevant at.
