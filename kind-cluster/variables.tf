variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "kind"
}

variable "kubernetes_version" {
  description = "Kind node image tag (kubernetes version) to run. Leave null for the kind default."
  type        = string
  default     = null
}

variable "flux_operator_version" {
  description = "Version of the controlplane/flux-operator Helm chart to install from OCI."
  type        = string
  default     = "0.19.0"
}

variable "flux_version" {
  description = "Version of Flux the FluxInstance should reconcile."
  type        = string
  default     = "2.4.0"
}

variable "flux_git_repository" {
  description = "Optional git repository URL to bootstrap Flux against. Leave empty to manage sync purely via OCIRepository/HelmRelease objects applied later."
  type        = string
  default     = "https://github.com/magnusp/declarative-deploys"
}

variable "flux_git_branch" {
  description = "Git branch Flux should reconcile when flux_git_repository is set."
  type        = string
  default     = "main"
}

variable "flux_git_path" {
  description = "Path within the git repository containing the cluster's Flux manifests."
  type        = string
  default     = "clusters/kind"
}

variable "kyverno_version" {
  description = "Kyverno chart version (OCI tag) for Flux to reconcile."
  type        = string
  default     = "3.9.0"
}
