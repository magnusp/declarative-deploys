# cert-manager is reconciled by Flux (not installed directly by Terraform),
# sourced from its OCI chart so it follows the same OCIRepository/HelmRelease
# pattern as other charts on this cluster.
resource "kubectl_manifest" "cert_manager_oci_repository" {
  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1beta2"
    kind       = "OCIRepository"
    metadata = {
      name      = "cert-manager"
      namespace = "flux-system"
    }
    spec = {
      interval = "1h"
      url      = "oci://quay.io/jetstack/charts/cert-manager"
      ref = {
        tag = var.cert_manager_version
      }
    }
  })

  depends_on = [kubectl_manifest.flux_instance]
}

resource "kubectl_manifest" "cert_manager_helm_release" {
  yaml_body = yamlencode({
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata = {
      name      = "cert-manager"
      namespace = "flux-system"
    }
    spec = {
      targetNamespace = "cert-manager"
      install = {
        createNamespace = true
      }
      interval = "1h"
      chartRef = {
        kind = "OCIRepository"
        name = "cert-manager"
      }
      values = {
        crds = {
          enabled = true
        }
      }
    }
  })

  depends_on = [kubectl_manifest.cert_manager_oci_repository]
}
