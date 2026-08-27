# Kyverno is reconciled by Flux, sourced from its OCI chart.
resource "kubectl_manifest" "kyverno_oci_repository" {
  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1beta2"
    kind       = "OCIRepository"
    metadata = {
      name      = "kyverno"
      namespace = "flux-system"
    }
    spec = {
      interval = "1h"
      url      = "oci://ghcr.io/kyverno/charts/kyverno"
      ref = {
        tag = var.kyverno_version
      }
    }
  })

  depends_on = [kubectl_manifest.flux_instance]
}

resource "kubectl_manifest" "kyverno_helm_release" {
  yaml_body = yamlencode({
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata = {
      name      = "kyverno"
      namespace = "flux-system"
    }
    spec = {
      targetNamespace = "kyverno"
      install = {
        createNamespace = true
      }
      interval = "1h"
      chartRef = {
        kind = "OCIRepository"
        name = "kyverno"
      }
    }
  })

  depends_on = [kubectl_manifest.kyverno_oci_repository]
}
