# Input variables for the github-oidc module.

variable "project" {
  description = "Project name used for naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "region" {
  description = "AWS region hosting the ECR repositories the CI role may push to. Used to build the scoped ECR resource ARNs."
  type        = string
  default     = "eu-central-1"
}

# ---------------------------------------------------------------------------
# GitHub repository identity (drives the OIDC trust policy subject).
#
# The default owner is derived from the application repo remote
# (github.com/charlesafuh/spring-petclinic-microservices) — the build workflow
# runs in the APPLICATION repo context, so the trust policy must reference the
# app repo fork, not the platform repo. Override per fork.
# ---------------------------------------------------------------------------
variable "github_owner" {
  description = "GitHub owner/org that owns the application repo fork (the repo whose Actions assume this role)."
  type        = string
  default     = "charlesafuh"

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub login (alphanumerics and hyphens)."
  }
}

variable "github_repo" {
  description = "Application repository name whose GitHub Actions build and push images."
  type        = string
  default     = "spring-petclinic-microservices"

  validation {
    condition     = length(var.github_repo) > 0
    error_message = "github_repo must not be empty."
  }
}

variable "github_branch" {
  description = "Branch the OIDC trust policy is restricted to. Only workflows on this branch of the app repo may assume the role."
  type        = string
  default     = "main"

  validation {
    condition     = length(var.github_branch) > 0
    error_message = "github_branch must not be empty."
  }
}

variable "role_name" {
  description = "Name of the GitHub Actions IAM role."
  type        = string
  default     = "petclinic-github-actions-role"
}

variable "oidc_audience" {
  description = "OIDC audience (client ID) expected in the GitHub token. aws-actions/configure-aws-credentials uses sts.amazonaws.com."
  type        = string
  default     = "sts.amazonaws.com"
}

# ---------------------------------------------------------------------------
# OIDC provider reuse. The GitHub OIDC provider is an account-global resource
# (one per AWS account). Set create_oidc_provider = false and supply
# existing_oidc_provider_arn when the account already has it (e.g. created by
# another stack) to avoid an EntityAlreadyExists error.
# ---------------------------------------------------------------------------
variable "create_oidc_provider" {
  description = "Whether to create the token.actions.githubusercontent.com IAM OIDC provider. Set false to reuse an existing one."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub IAM OIDC provider to reuse when create_oidc_provider = false."
  type        = string
  default     = ""

  validation {
    condition     = var.existing_oidc_provider_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token.actions.githubusercontent.com$", var.existing_oidc_provider_arn))
    error_message = "existing_oidc_provider_arn must be empty or a valid GitHub OIDC provider ARN."
  }
}

# ---------------------------------------------------------------------------
# ECR scoping. The role is granted push access only to these repositories.
# By default it is scoped to the petclinic-{env} namespaces in this account;
# GetAuthorizationToken is account-wide (AWS does not support resource-level
# permissions on that action).
# ---------------------------------------------------------------------------
variable "ecr_repository_namespaces" {
  description = "ECR repository namespaces (petclinic-{env}) the CI role may push to. Used to build scoped resource ARNs of the form repository/{namespace}/*."
  type        = list(string)
  default     = ["petclinic-dev", "petclinic-prod"]

  validation {
    condition     = length(var.ecr_repository_namespaces) > 0
    error_message = "ecr_repository_namespaces must contain at least one namespace."
  }
}

variable "ecr_repository_arns" {
  description = "Explicit ECR repository ARNs the CI role may push to. Overrides ecr_repository_namespaces when non-empty. Must be specific ARNs (no bare '*')."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.ecr_repository_arns : a != "*" && can(regex("^arn:aws:ecr:", a))])
    error_message = "ecr_repository_arns must be ECR resource ARNs (arn:aws:ecr:...), never a bare '*'."
  }
}

variable "tags" {
  description = "Additional tags merged onto created resources (on top of provider default_tags)."
  type        = map(string)
  default     = {}
}
