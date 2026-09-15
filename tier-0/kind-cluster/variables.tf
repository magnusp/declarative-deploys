variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "tier-0"
}

variable "kubernetes_version" {
  description = "Kind node image tag (kubernetes version) to run. Leave null for the kind default."
  type        = string
  default     = null
}
