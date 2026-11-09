# Outputs for the secrets module (secret ARNs for External Secrets Operator).

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (petclinic/{env}/openai-api-key)."
  value       = aws_secretsmanager_secret.openai.arn
}

output "openai_secret_name" {
  description = "Secrets Manager secret name for the OpenAI API key."
  value       = aws_secretsmanager_secret.openai.name
}

output "git_username_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git username (null when not managed)."
  value       = one(aws_secretsmanager_secret.git_username[*].arn)
}

output "git_password_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git password (null when not managed)."
  value       = one(aws_secretsmanager_secret.git_password[*].arn)
}
