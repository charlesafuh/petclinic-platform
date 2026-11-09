output "aws_account_id" {
  description = "AWS account ID these global resources live in."
  value       = data.aws_caller_identity.current.account_id
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions CI role. Set as the AWS_ROLE_ARN secret in the application repo."
  value       = module.github_oidc.role_arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions CI role."
  value       = module.github_oidc.role_name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (created or reused)."
  value       = module.github_oidc.oidc_provider_arn
}

output "github_oidc_subject" {
  description = "The OIDC trust subject the CI role is restricted to."
  value       = module.github_oidc.oidc_subject
}

output "ecr_repository_arns" {
  description = "ECR repository ARNs the CI role may push to."
  value       = module.github_oidc.ecr_repository_arns
}
