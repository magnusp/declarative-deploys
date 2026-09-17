provider "kind" {}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role  = "control-plane"
      image = var.kubernetes_version == null ? null : "kindest/node:${var.kubernetes_version}"
    }

    node {
      role  = "worker"
      image = var.kubernetes_version == null ? null : "kindest/node:${var.kubernetes_version}"
    }
  }
}
