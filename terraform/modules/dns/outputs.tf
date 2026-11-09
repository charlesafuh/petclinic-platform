# Outputs for the dns module.

output "zone_id" {
  description = "Route 53 hosted zone ID (looked up, not created)."
  value       = data.aws_route53_zone.this.zone_id
}

output "zone_name_servers" {
  description = "Name servers for the hosted zone (for registrar delegation)."
  value       = data.aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "ARN of the validated ACM certificate (use in the Ingress certificate-arn annotation)."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "certificate_domain" {
  description = "Primary domain on the ACM certificate."
  value       = local.certificate_domain
}

output "record_fqdn" {
  description = "Fully-qualified hostname for this environment's app record."
  value       = local.record_fqdn
}

output "alias_record_created" {
  description = "Whether the ALB alias A record has been created (false until the ALB is supplied)."
  value       = local.create_alias
}
