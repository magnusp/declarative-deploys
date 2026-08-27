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
