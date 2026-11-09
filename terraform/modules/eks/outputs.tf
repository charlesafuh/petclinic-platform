# Outputs for the eks module.

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed primary cluster security group ID."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (for IRSA trust policies)."
  value       = aws_iam_openid_connect_provider.oidc.arn
}

output "oidc_provider_url" {
  description = "URL of the IAM OIDC provider (issuer, without scheme)."
  value       = local.oidc_issuer_host
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "ARN of the worker node IAM role."
  value       = aws_iam_role.node.arn
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI Driver IRSA role."
  value       = aws_iam_role.ebs_csi.arn
}

output "lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role (annotate the aws-load-balancer-controller ServiceAccount with this)."
  value       = aws_iam_role.lb_controller.arn
}

output "lb_controller_version" {
  description = "Controller appVersion the IAM policy is pinned to; pass to the install script."
  value       = var.lb_controller_version
}

output "eso_role_arn" {
  description = "ARN of the External Secrets Operator IRSA role (annotate the external-secrets-sa ServiceAccount with this via eks.amazonaws.com/role-arn)."
  value       = aws_iam_role.eso.arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for this cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}
