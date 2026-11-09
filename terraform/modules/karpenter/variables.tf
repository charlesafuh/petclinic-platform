# Input variables for the karpenter module.

variable "project" {
  description = "Project name used for naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Drives naming petclinic-{env}-*."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

variable "cluster_name" {
  description = "EKS cluster name. Scopes eks:DescribeCluster and tags Karpenter discovers nodes with."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster IAM OIDC provider (from the eks module). Used for the Karpenter controller IRSA trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "Host of the cluster OIDC issuer without scheme (from the eks module, e.g. oidc.eks.eu-central-1.amazonaws.com/id/XXXX). Used to build the IRSA sub/aud trust conditions."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role (from the eks module). Karpenter passes this role to launched nodes and it backs the Karpenter node instance profile."
  type        = string
}

variable "tags" {
  description = "Additional tags merged onto created resources (on top of provider default_tags)."
  type        = map(string)
  default     = {}
}
