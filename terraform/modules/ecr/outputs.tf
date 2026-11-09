# Outputs for the ecr module.

output "repository_urls" {
  description = "Map of service name -> ECR repository URL."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service name -> ECR repository ARN."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.arn }
}

output "repository_names" {
  description = "Map of service name -> ECR repository name (petclinic-{env}/{service})."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.name }
}

output "registry_id" {
  description = "The account registry ID hosting these repositories."
  value       = values(aws_ecr_repository.this)[0].registry_id
}
