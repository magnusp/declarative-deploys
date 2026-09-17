# The SpiceDB Operator's CRDs (notably SpiceDBCluster) must exist before Flux's
# git-synced Kustomization can apply clusters/kind/spicedb-cluster.yaml, which
# instantiates a SpiceDBCluster. If the operator's GitRepository/Kustomization
# were themselves resources inside that same git-synced Kustomization, the
# whole apply would deadlock on a cold cluster: kustomize-controller validates
# the entire manifest set together, so the SpiceDBCluster CR's failed dry-run
# (no CRD yet) blocks the operator's own GitRepository/Kustomization from ever
# being created, and the CRD never gets installed. Applying the operator
# bootstrap directly via OpenTofu — the same pattern kyverno.tf uses — breaks
# that cycle: it's guaranteed to exist and start reconciling independently of
# whether the git-synced Kustomization has succeeded yet.

resource "kubectl_manifest" "spicedb_operator_git_repository" {
  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = "spicedb-operator"
      namespace = "flux-system"
    }
    spec = {
      interval = "2h"
      url      = "https://github.com/authzed/spicedb-operator"
      ref = {
        tag = "v1.26.0"
      }
    }
  })

  depends_on = [kubectl_manifest.flux_instance]
}

resource "kubectl_manifest" "spicedb_operator_kustomization" {
  yaml_body = yamlencode({
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "spicedb-operator"
      namespace = "flux-system"
    }
    spec = {
      interval = "2h"
      path     = "./config"
      prune    = true
      wait     = true
      sourceRef = {
        kind = "GitRepository"
        name = "spicedb-operator"
      }
    }
  })

  depends_on = [kubectl_manifest.spicedb_operator_git_repository]
}

# RBAC extension granting spicedb-operator permissions to manage
# PodDisruptionBudgets and EndpointSlices. Kept alongside the operator's own
# bootstrap for the same reason: it must exist before the operator reconciles
# SpiceDBCluster resources, independent of the git-synced Kustomization.
resource "kubectl_manifest" "spicedb_operator_pdb_extension_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = "spicedb-operator-pdb-extension"
    }
    rules = [
      {
        apiGroups = ["policy"]
        resources = ["poddisruptionbudgets"]
        verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
      },
      {
        apiGroups = ["discovery.k8s.io"]
        resources = ["endpointslices"]
        verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
      },
    ]
  })

  depends_on = [kubectl_manifest.flux_instance]
}

resource "kubectl_manifest" "spicedb_operator_pdb_extension_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "spicedb-operator-pdb-extension"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "spicedb-operator-pdb-extension"
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = "spicedb-operator"
        namespace = "spicedb-operator"
      },
    ]
  })

  depends_on = [kubectl_manifest.spicedb_operator_pdb_extension_role]
}
