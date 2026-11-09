# Outputs for the github-oidc module.

output "role_arn" {
  description = "ARN of the GitHub Actions IAM role. Store as the AWS_ROLE_ARN GitHub secret in the app repo."
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions IAM role."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (created or reused)."
  value       = local.oidc_provider_arn
}

output "oidc_subject" {
  description = "The OIDC trust subject the role is restricted to (repo:{owner}/{repo}:ref:refs/heads/{branch})."
  value       = local.oidc_subject
}

output "ecr_repository_arns" {
  description = "The ECR repository ARNs the role is permitted to push to."
  value       = local.ecr_resource_arns
}
