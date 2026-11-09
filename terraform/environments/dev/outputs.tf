output "aws_account_id" {
  description = "AWS account ID this environment is deployed into."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region this environment is deployed into."
  value       = var.aws_region
}

output "environment" {
  description = "Environment name."
  value       = var.environment
}

# --- Networking (VPC) -------------------------------------------------------

output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the dev public subnets."
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS control plane security group ID."
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = module.vpc.alb_sg_id
}

# --- EKS --------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (for IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "IAM OIDC provider URL (issuer without scheme)."
  value       = module.eks.oidc_provider_url
}

output "node_group_name" {
  description = "Managed node group name."
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "Worker node IAM role ARN."
  value       = module.eks.node_role_arn
}

output "ebs_csi_role_arn" {
  description = "EBS CSI Driver IRSA role ARN."
  value       = module.eks.ebs_csi_role_arn
}

output "eso_role_arn" {
  description = "External Secrets Operator IRSA role ARN (annotate the external-secrets-sa ServiceAccount with this)."
  value       = module.eks.eso_role_arn
}

output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IRSA role ARN (for scripts/install-lb-controller.sh)."
  value       = module.eks.lb_controller_role_arn
}

output "lb_controller_version" {
  description = "Controller appVersion the IAM policy is pinned to."
  value       = module.eks.lb_controller_version
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for this cluster."
  value       = module.eks.kubeconfig_command
}

# --- ECR --------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "Map of service name -> ECR repository URL."
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service name -> ECR repository ARN."
  value       = module.ecr.repository_arns
}

output "ecr_repository_names" {
  description = "Map of service name -> ECR repository name (petclinic-{env}/{service})."
  value       = module.ecr.repository_names
}

output "ecr_registry_id" {
  description = "ECR registry (account) ID hosting the repositories."
  value       = module.ecr.registry_id
}

# --- RDS --------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS endpoint hostname (connect on port 3306)."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS listening port."
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "RDS instance identifier."
  value       = module.rds.db_instance_id
}

output "rds_jdbc_url" {
  description = "JDBC connection string for the shared petclinic database."
  value       = module.rds.jdbc_url
}

output "rds_credentials_secret_arn" {
  description = "Secrets Manager ARN for the RDS credentials (petclinic/dev/rds-credentials)."
  value       = module.rds.secret_arn
}

# --- Secrets ----------------------------------------------------------------

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (petclinic/dev/openai-api-key)."
  value       = module.secrets.openai_secret_arn
}

# --- DNS & Ingress ----------------------------------------------------------

output "dns_zone_id" {
  description = "Route 53 hosted zone ID (null when the DNS module is disabled)."
  value       = one(module.dns[*].zone_id)
}

output "dns_certificate_arn" {
  description = "Validated ACM certificate ARN for the Ingress annotation (null until domain_name is set)."
  value       = one(module.dns[*].certificate_arn)
}

output "dns_record_fqdn" {
  description = "Public hostname for the dev app (petclinic-dev.{domain_name})."
  value       = one(module.dns[*].record_fqdn)
}

# --- Karpenter (E-14) -------------------------------------------------------

output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN. Annotate the karpenter ServiceAccount with this."
  value       = module.karpenter.karpenter_role_arn
}

output "karpenter_queue_name" {
  description = "Karpenter SQS interruption queue name (Helm settings.interruptionQueue)."
  value       = module.karpenter.karpenter_queue_name
}

output "karpenter_instance_profile_name" {
  description = "Karpenter node instance profile name (EC2NodeClass spec.instanceProfile)."
  value       = module.karpenter.karpenter_instance_profile_name
}
