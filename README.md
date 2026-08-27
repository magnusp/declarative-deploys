# declarative-deploys

Local kind cluster bootstrapped with Flux, and the Helm charts it's meant to run.

* `kind-cluster/` — OpenTofu stack that creates the kind cluster and installs Flux
  (via the `flux-operator` OCI chart) plus Kyverno (as a Flux
  `HelmRelease`).
* `charts/` — Helm charts owned by platform engineering, consumed by development
  teams, published to GitHub Packages (GHCR) via a manual GitHub Actions workflow.
* `clusters/kind/` — the manifests Flux reconciles onto the cluster: an
  `OCIRepository`/`HelmRelease` pair per workload, sourced straight from this git
  repository (see `flux_git_repository`/`flux_git_path` in `kind-cluster/variables.tf`).
* `apps-source/` — a simulated application repository: an nginx-based image plus
  the `archetype-backend` values it should be deployed with, published by their
  own GitHub Actions workflows (see below).

## Standing up, checking, and tearing down the cluster

All cluster lifecycle commands go through `kind-cluster/cluster.sh`, which wraps
the OpenTofu stack. Run it from the `kind-cluster/` directory:

```sh
cd kind-cluster

./cluster.sh up      # create the kind cluster, install Flux + Kyverno, then check
./cluster.sh check   # wait for Flux and Kyverno to report Ready, print pod status
./cluster.sh down    # destroy the OpenTofu stack and the kind cluster
```

`up` requires the tools declared in `kind-cluster/mise.toml` (`kind`, `opentofu`,
`helm`, `kubectl`, `yq`) — install them first with `mise install`.

`check` and `up` both read the cluster's kubeconfig from OpenTofu state to talk to
the cluster; they don't require you to export `KUBECONFIG` yourself.

Once Flux is running, it reconciles `clusters/kind/` from this repository's `main`
branch. `clusters/kind/ocirepository-archetype-backend.yaml` tracks a chart version
published to GHCR — reconciliation requires both that the version has actually
been published (see below) and that its GHCR package is set to public
visibility (a separate, package-level setting only available after the first
publish; go to the package's own settings page on GHCR to flip it).

Flux needs no credentials for any of this: the repository is public, and every
source under `clusters/kind/` assumes its target (git or GHCR package) is
public too. If you ever add a source that isn't public, apply its pull secret
manually (`kubectl create secret ... -n flux-system`, referenced via that
source's `secretRef`/`pullSecret`) rather than committing a credential here.

## Simulated application: apps-source/

`apps-source/` stands in for a development team's own repository. It builds an
image on top of `nginx` with a custom `index.html`, and carries the
`archetype-backend` chart values (`values.yaml`) that describe how it wants to
be deployed. Two workflows drive it:

* **`Build app image`** (`.github/workflows/build-app-image.yaml`) — builds
  `apps-source/` and pushes `ghcr.io/magnusp/apps/archetype-backend:<commit-sha>`,
  attesting build provenance for the pushed digest.
* **`Bump archetype-backend values`**
  (`.github/workflows/publish-app-values.yaml`) — takes an `image_tag` input,
  writes it into `apps-source/values.yaml`, and pushes the `apps-source/`
  directory (containing `values.yaml`) as an OCI artifact to
  `ghcr.io/magnusp/apps/archetype-backend-values:latest`, also attested.

This is the "gitops version bump": `latest` is a mutable tag, so publishing a
new values artifact *is* the deploy. Flux's `archetype-backend-values`
`OCIRepository` (`clusters/kind/ocirepository-archetype-backend-values.yaml`)
re-pulls it; the `ArtifactGenerator`
(`clusters/kind/artifactgenerator-archetype-backend.yaml`) deep-merges the base
Helm chart and the application `values.yaml` into an `ExternalArtifact`; and the
`archetype-backend-demo` `HelmRelease` watches this artifact directly, upgrading
immediately — no commit against `clusters/kind/` required. In a real setup you'd
typically chain the two workflows (build image, then bump values with that image's
tag) rather than run them independently.

### Publishing a new version (app team runbook)

To ship a change to the application, from the GitHub Actions tab:

1. **Merge your change** to `main` (or whichever branch/commit you want to
   build — the image is tagged with that commit's SHA either way).
2. Run **`Build app image`** on that commit. No inputs — it always builds and
   pushes `ghcr.io/magnusp/apps/archetype-backend:<commit-sha>`.
3. Once it succeeds, note the commit SHA (`git rev-parse HEAD`, or read it off
   the run) and run **`Bump archetype-backend values`** with `image_tag` set
   to that SHA.
4. That's the deploy. Flux picks up the new `archetype-backend-values` artifact
   on its own, composes the `ExternalArtifact`, and immediately triggers the
   `HelmRelease` upgrade — no commit or manual apply needed. Confirm it rolled out:

   ```sh
   kubectl get helmrelease -n flux-system archetype-backend-demo
   kubectl get pods -n default -l app.kubernetes.io/instance=archetype-backend-demo
   kubectl get deploy -n default -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
   ```

   The last command should print `archetype-backend:<the-sha-you-bumped-to>`.

If you need to change something other than the image (replica count, chart
version, etc.), edit `apps-source/values.yaml` directly before step 3 — the
values workflow packages whatever is in that file at run time, it doesn't
generate it from scratch.

## Kyverno policies

Kyverno is installed as a Flux `HelmRelease` (`kind-cluster/kyverno.tf`). Its `ClusterPolicy`
objects live under `clusters/kind/` alongside the workloads they target.

`clusters/kind/clusterpolicy-archetype-backend-image-revision.yaml` is a first
test policy: it mutates the `default-archetype-backend-demo` Deployment
(Flux names the underlying Helm release `<targetNamespace>-<HelmRelease name>`
when a release name isn't set explicitly), reading the
`org.opencontainers.image.revision` OCI label off its own container image (via
Kyverno's `imageRegistry` context) and writing it onto the pod template as the
`example.com/image-revision` annotation. `build-app-image.yaml` sets that label
to the commit SHA at build time, so once Kyverno mutates a rollout you can
confirm it landed with:

```sh
kubectl get deploy -n default default-archetype-backend-demo \
  -o jsonpath='{.spec.template.metadata.annotations}'
```

This only reads a plain image-config label, not a signed attestation
predicate — verifying an actual signed attestation at admission time would use
Kyverno's `verifyImages`/`attestations` instead, which needs the images to be
cosign-signed.

## Verifying attestations of published artifacts

Every publish workflow in this repo (`Publish Helm chart`, `Build app image`,
`Bump archetype-backend values`) attests build provenance for what it pushes.
To verify that an artifact was produced by its workflow (and not pushed by
hand), use the GitHub CLI against any of:

```sh
gh attestation verify oci://ghcr.io/magnusp/charts/<chart>:<version> --owner magnusp
gh attestation verify oci://ghcr.io/magnusp/apps/archetype-backend:<commit-sha> --owner magnusp
gh attestation verify oci://ghcr.io/magnusp/apps/archetype-backend-values:latest --owner magnusp
```

This confirms the artifact's digest matches a provenance attestation signed by
a GitHub Actions run in this repository, and prints the workflow run that
produced it.

You can also list all attestations for a given digest without verifying:

```sh
gh attestation verify \
  oci://ghcr.io/magnusp/charts/<chart>:<version> \
  --owner magnusp \
  --format json | jq
```
