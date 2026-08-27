# Policy Reporter is reconciled by Flux from the Kyverno Helm repository.
resource "kubectl_manifest" "policy_reporter_helm_repository" {
  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "HelmRepository"
    metadata = {
      name      = "policy-reporter"
      namespace = "flux-system"
    }
    spec = {
      interval = "1h"
      url      = "https://kyverno.github.io/policy-reporter"
    }
  })

  depends_on = [kubectl_manifest.flux_instance]
}

# Namespace for Policy Reporter resources and PVC
resource "kubectl_manifest" "policy_reporter_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "policy-reporter"
    }
  })

  depends_on = [kind_cluster.this]
}

# Persistent Volume Claim for SQLite storage backed by kind's standard local-path provisioner
resource "kubectl_manifest" "policy_reporter_sqlite_pvc" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "policy-reporter-sqlite-pvc"
      namespace = "policy-reporter"
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = "1Gi"
        }
      }
    }
  })

  depends_on = [kubectl_manifest.policy_reporter_namespace]
}

resource "kubectl_manifest" "policy_reporter_helm_release" {
  yaml_body = yamlencode({
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata = {
      name      = "policy-reporter"
      namespace = "flux-system"
    }
    spec = {
      targetNamespace = "policy-reporter"
      install = {
        createNamespace = false
      }
      interval = "1h"
      chart = {
        spec = {
          chart   = "policy-reporter"
          version = var.policy_reporter_version
          sourceRef = {
            kind = "HelmRepository"
            name = "policy-reporter"
          }
        }
      }
      values = {
        sqliteVolume = {
          persistentVolumeClaim = {
            claimName = "policy-reporter-sqlite-pvc"
          }
        }
        ui = {
          enabled = true
        }
        kyvernoPlugin = {
          enabled = true
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.policy_reporter_helm_repository,
    kubectl_manifest.policy_reporter_sqlite_pvc,
    kubectl_manifest.kyverno_helm_release,
  ]
}
