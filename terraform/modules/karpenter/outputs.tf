# Outputs for the karpenter module.

output "karpenter_role_arn" {
  description = "ARN of the Karpenter controller IRSA role. Annotate the karpenter ServiceAccount with this (eks.amazonaws.com/role-arn)."
  value       = aws_iam_role.controller.arn
}

output "karpenter_queue_name" {
  description = "Name of the SQS interruption queue. Pass to Helm as settings.interruptionQueue."
  value       = aws_sqs_queue.interruption.name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile for Karpenter-launched nodes. Referenced by name in the EC2NodeClass (spec.instanceProfile)."
  value       = aws_iam_instance_profile.node.name
}
