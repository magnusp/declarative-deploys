# declarative-deploys

Local kind cluster bootstrapped with Flux, and the Helm charts it's meant to run.

* `kind-cluster/` — OpenTofu stack that creates the kind cluster and installs Flux
  (via the `flux-operator` OCI chart) plus cert-manager (as a Flux `HelmRelease`).
* `charts/` — Helm charts owned by platform engineering, consumed by development
  teams, published to GitHub Packages (GHCR) via a manual GitHub Actions workflow.
* `clusters/kind/` — the manifests Flux reconciles onto the cluster: an
  `OCIRepository`/`HelmRelease` pair per workload, sourced straight from this git
  repository (see `flux_git_repository`/`flux_git_path` in `kind-cluster/variables.tf`).

## Standing up, checking, and tearing down the cluster

All cluster lifecycle commands go through `kind-cluster/cluster.sh`, which wraps
the OpenTofu stack. Run it from the `kind-cluster/` directory:

```sh
cd kind-cluster

./cluster.sh up      # create the kind cluster, install Flux + cert-manager, then check
./cluster.sh check   # wait for Flux and cert-manager to report Ready, print pod status
./cluster.sh down    # destroy the OpenTofu stack and the kind cluster
```

`up` requires the tools declared in `kind-cluster/mise.toml` (`kind`, `opentofu`,
`helm`, `kubectl`, `yq`) — install them first with `mise install`.

`check` and `up` both read the cluster's kubeconfig from OpenTofu state to talk to
the cluster; they don't require you to export `KUBECONFIG` yourself.

Once Flux is running, it reconciles `clusters/kind/` from this repository's `main`
branch. `clusters/kind/ocirepository-archetype-backend.yaml` tracks a chart version
published to GHCR (see below) — it can only reconcile successfully once that
version has actually been published.

## Giving Flux a GitHub token

Flux needs a GitHub credential for two things: cloning this repository (the
`GitRepository` source) and pulling chart packages from GHCR (each
`OCIRepository` source). These need two different kinds of token, because
**fine-grained PATs cannot authenticate to GHCR** — GitHub hasn't shipped a
`packages` permission for them yet, only for classic tokens. So:

* **GITHUB_TOKEN** — a fine-grained PAT scoped to this repository with
  **Contents: Read-only**. Used for the git clone.
* **GHCR_TOKEN** — a **classic** PAT with the **`read:packages`** scope
  (classic tokens aren't repo-scoped, so this grants read access to all your
  packages). Used for GHCR pulls.

Both read from secrets in `flux-system` that `cluster.sh` applies for
you — they are not managed by Terraform, since a token shouldn't live in
state or in a `.tf` file.

```sh
cd kind-cluster
export GITHUB_USERNAME=<your-github-username>
export GITHUB_TOKEN=<the-fine-grained-pat>
export GHCR_TOKEN=<the-classic-pat>
./cluster.sh secrets
```

This creates `flux-git-auth` (referenced by the `FluxInstance`'s
`sync.pullSecret`) and `ghcr-pull` (referenced by each `OCIRepository`'s
`secretRef`) in the `flux-system` namespace. Re-run it whenever a token is
rotated.

## Verifying attestations of published charts

Charts are published to GHCR by the `Publish Helm chart` workflow
(`.github/workflows/publish-chart.yaml`), which attests build provenance for
every chart it pushes. To verify that a chart version was produced by that
workflow (and not pushed by hand), use the GitHub CLI:

```sh
gh attestation verify \
  oci://ghcr.io/fortnox-lab/charts/<chart>:<version> \
  --owner fortnox-lab
```

This confirms the artifact's digest matches a provenance attestation signed by
a GitHub Actions run in this repository, and prints the workflow run that
produced it. Replace `<chart>` and `<version>` with the chart name (e.g.
`archetype-backend`) and the version you want to check.

You can also list all attestations for a given digest without verifying:

```sh
gh attestation verify \
  oci://ghcr.io/fortnox-lab/charts/<chart>:<version> \
  --owner fortnox-lab \
  --format json | jq
```
