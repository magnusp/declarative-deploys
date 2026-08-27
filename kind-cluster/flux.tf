# Flux is installed via the flux-operator Helm chart, pulled directly from its
# OCI registry (oci://ghcr.io/controlplane/charts/flux-operator) rather than a
# traditional Helm repo, since we standardize on OCI-hosted charts.
resource "helm_release" "flux_operator" {
  name       = "flux-operator"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-operator"
  version    = var.flux_operator_version

  create_namespace = true

  depends_on = [kind_cluster.this]
}

# The FluxInstance CR tells flux-operator which Flux controllers to run and,
# optionally, which git repository to sync. Source controllers for both
# OCIRepository and GitRepository are enabled so charts can be pulled from
# OCI registries by default, with git sync available when configured.
resource "kubectl_manifest" "flux_instance" {
  yaml_body = yamlencode({
    apiVersion = "fluxcd.controlplane.io/v1"
    kind       = "FluxInstance"
    metadata = {
      name      = "flux"
      namespace = "flux-system"
    }
    spec = {
      distribution = {
        version  = var.flux_version
        registry = "ghcr.io/fluxcd"
      }
      components = [
        "source-controller",
        "kustomize-controller",
        "helm-controller",
        "notification-controller",
      ]
      cluster = {
        multitenant = false
        networkPolicy = true
      }
      sync = var.flux_git_repository == "" ? null : {
        kind = "GitRepository"
        url  = var.flux_git_repository
        ref  = "refs/heads/${var.flux_git_branch}"
        path = var.flux_git_path
      }
    }
  })

  depends_on = [helm_release.flux_operator]
}
