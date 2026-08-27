output "kubeconfig" {
  description = "Kubeconfig for the kind cluster."
  value       = kind_cluster.this.kubeconfig
  sensitive   = true
}

output "cluster_endpoint" {
  description = "API server endpoint of the kind cluster."
  value       = kind_cluster.this.endpoint
}
