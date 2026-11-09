# Module: karpenter (PETPLAT-73)
#
# AWS prerequisites for running Karpenter on EKS:
#   - Controller IRSA role (trusts the karpenter ServiceAccount via the cluster
#     OIDC provider) + a scoped controller policy.
#   - Node instance profile (petclinic-{env}-karpenter-node-profile) backed by
#     the existing EKS node role. Referenced by name from the EC2NodeClass.
#   - SQS interruption queue + a queue policy letting EventBridge publish to it.
#   - EventBridge rules for the 4 interruption/health events -> the SQS queue.
#
# The Helm install of the controller and the NodePool/EC2NodeClass CRDs live in
# k8s/base/karpenter/.
#
# Base tags (Project, Environment, ManagedBy) come from the provider
# default_tags block in the environment root module.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  # EXACT name referenced by the EC2NodeClass (spec.instanceProfile). A mismatch
  # means launched nodes cannot authenticate to the cluster.
  instance_profile_name = "${local.name_prefix}-karpenter-node-profile"
  controller_role_name  = "${local.name_prefix}-karpenter-role"
  queue_name            = "${local.name_prefix}-karpenter-interruption"

  # Node role name derived from its ARN (last path segment) for the instance profile.
  node_role_name = element(split("/", var.node_role_arn), length(split("/", var.node_role_arn)) - 1)

  partition   = data.aws_partition.current.partition
  region      = data.aws_region.current.name
  account_id  = data.aws_caller_identity.current.account_id
  cluster_arn = "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"
}

# ===========================================================================
# Node instance profile (attached to Karpenter-launched EC2 instances).
# ===========================================================================
resource "aws_iam_instance_profile" "node" {
  name = local.instance_profile_name
  role = local.node_role_name

  tags = merge(var.tags, {
    Name = local.instance_profile_name
  })
}

# ===========================================================================
# SQS interruption queue + EventBridge->SQS publish policy.
# ===========================================================================
resource "aws_sqs_queue" "interruption" {
  name                      = local.queue_name
  message_retention_seconds = 300
  # 20-minute visibility timeout (PETPLAT-73).
  visibility_timeout_seconds = 1200
  sqs_managed_sse_enabled    = true

  tags = merge(var.tags, {
    Name = local.queue_name
  })
}

# Without this policy the EventBridge rules below cannot deliver to the queue,
# so Karpenter never sees interruption events and spot terminations are not
# handled gracefully.
data "aws_iam_policy_document" "queue" {
  statement {
    sid    = "AllowEventBridgeAndSQSPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.queue.json
}

# ===========================================================================
# EventBridge rules -> SQS. Four event sources Karpenter consumes to drain
# nodes ahead of interruptions and reconcile capacity.
# ===========================================================================
locals {
  event_rules = {
    spot-interruption = {
      description = "EC2 Spot Instance Interruption Warning"
      pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    rebalance = {
      description = "EC2 Instance Rebalance Recommendation"
      pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    instance-state-change = {
      description = "EC2 Instance State-change Notification"
      pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
    scheduled-change = {
      description = "AWS Health scheduled change event"
      pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name          = "${local.name_prefix}-karpenter-${each.key}"
  description   = "Karpenter interruption handling: ${each.value.description}"
  event_pattern = jsonencode(each.value.pattern)

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-karpenter-${each.key}"
  })
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

# ===========================================================================
# Karpenter controller IRSA role.
# Trust is scoped to the karpenter ServiceAccount in kube-system via the
# cluster OIDC provider (never a hardcoded account/provider).
# ===========================================================================
data "aws_iam_policy_document" "controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = local.controller_role_name
  description        = "Karpenter controller (IRSA) for cluster ${var.cluster_name}."
  assume_role_policy = data.aws_iam_policy_document.controller_assume.json

  tags = merge(var.tags, {
    Name = local.controller_role_name
  })
}

# Controller permissions. EC2 provisioning is broad (Karpenter manages the full
# instance lifecycle — per the technical spec), while the sensitive grants are
# scoped: SQS to this queue, eks:DescribeCluster to this cluster, and crucially
# iam:PassRole to the node role ONLY.
data "aws_iam_policy_document" "controller" {
  # Karpenter needs broad EC2 to create/describe/tag/terminate fleet capacity.
  statement {
    sid    = "AllowEC2FleetManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  # SSM public AMI parameters (Karpenter resolves the AL2023 ARM AMI).
  statement {
    sid       = "AllowSSMReadActions"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"]
  }

  # Spot price/offering lookups for instance selection.
  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # Interruption queue — scoped to THIS queue only.
  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.interruption.arn]
  }

  # Cluster endpoint/CA discovery — scoped to THIS cluster only.
  statement {
    sid       = "AllowEksDescribeCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [local.cluster_arn]
  }

  # iam:PassRole MUST be scoped (not "*") to prevent privilege escalation.
  # PassRole targets the ROLE being passed (the node role) — an instance profile
  # is not a valid PassRole resource — and is further constrained to EC2.
  statement {
    sid       = "AllowPassingNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.node_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "controller" {
  name        = "${local.controller_role_name}-policy"
  description = "Karpenter controller permissions (EC2 fleet, SSM/pricing read, scoped SQS/EKS/PassRole)."
  policy      = data.aws_iam_policy_document.controller.json

  tags = merge(var.tags, {
    Name = "${local.controller_role_name}-policy"
  })
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}
