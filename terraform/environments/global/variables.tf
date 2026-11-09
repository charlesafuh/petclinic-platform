variable "aws_region" {
  description = "AWS region. The GitHub Actions role pushes to ECR in this region."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Project name used for naming and tagging."
  type        = string
  default     = "petclinic"
}

# --- GitHub OIDC (CI) -------------------------------------------------------

variable "github_owner" {
  description = "GitHub owner of the application repo fork whose Actions assume the CI role. Derived from the app repo remote."
  type        = string
  default     = "charlesafuh"
}

variable "github_repo" {
  description = "Application repository name whose GitHub Actions build and push images."
  type        = string
  default     = "spring-petclinic-microservices"
}

variable "github_branch" {
  description = "Branch the OIDC trust is restricted to."
  type        = string
  default     = "main"
}

variable "ecr_repository_namespaces" {
  description = "ECR namespaces (petclinic-{env}) the CI role may push to. The role is account-global and covers both dev and prod."
  type        = list(string)
  default     = ["petclinic-dev", "petclinic-prod"]
}

variable "create_oidc_provider" {
  description = "Whether to create the GitHub IAM OIDC provider. Set false (and supply existing_oidc_provider_arn) if the account already has it."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider to reuse when create_oidc_provider = false."
  type        = string
  default     = ""
}
