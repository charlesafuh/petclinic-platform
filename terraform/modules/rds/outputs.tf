# Outputs for the rds module.

output "endpoint" {
  description = "RDS endpoint hostname (no port). Use with port 3306 for JDBC."
  value       = aws_db_instance.this.address
}

output "endpoint_with_port" {
  description = "RDS endpoint as host:port (as returned by the RDS API)."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "RDS listening port."
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS instance ARN."
  value       = aws_db_instance.this.arn
}

output "database_name" {
  description = "Name of the shared application database."
  value       = aws_db_instance.this.db_name
}

output "jdbc_url" {
  description = "JDBC connection string for the shared database (for K8s ConfigMaps)."
  value       = "jdbc:mysql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
}

output "secret_arn" {
  description = "Secrets Manager ARN for the RDS credentials (for External Secrets Operator)."
  value       = aws_secretsmanager_secret.rds.arn
}

output "secret_name" {
  description = "Secrets Manager secret name (petclinic/{env}/rds-credentials)."
  value       = aws_secretsmanager_secret.rds.name
}
