# Global / account-level root module.
#
# Holds resources that are NOT per-environment: the GitHub Actions OIDC provider
# and the CI IAM role (one per account, pushes to both dev and prod ECR).
# Separate state key: petclinic/global/terraform.tfstate.

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC federation (PETPLAT-52).
# The CI role is assumed via sts:AssumeRoleWithWebIdentity, trust-scoped to the
# app repo's main branch, with ECR-push-only permissions.
# ---------------------------------------------------------------------------
module "github_oidc" {
  source = "../../modules/github-oidc"

  project = var.project
  region  = var.aws_region

  github_owner  = var.github_owner
  github_repo   = var.github_repo
  github_branch = var.github_branch

  ecr_repository_namespaces = var.ecr_repository_namespaces

  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
}
