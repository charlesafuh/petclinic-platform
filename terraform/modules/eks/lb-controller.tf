# ===========================================================================
# IRSA role for the AWS Load Balancer Controller (PETPLAT-29)
#
# The controller runs as ServiceAccount aws-load-balancer-controller in
# kube-system and provisions ALBs for Ingress resources. The IAM policy is the
# official policy published by the controller project, pinned to the same
# appVersion the Helm chart installs. The policy file name embeds the version
# (lb-controller-iam-policy-${var.lb_controller_version}.json), so bumping
# var.lb_controller_version without also adding the matching JSON file fails the
# plan loudly instead of silently running a mismatched policy.
# ===========================================================================

data "aws_caller_identity" "current" {}

locals {
  lb_controller_policy_file = "${path.module}/lb-controller-iam-policy-${var.lb_controller_version}.json"

  # Build SG ARNs for the guardrail Deny from the protected SG IDs.
  lb_protected_sg_arns = [
    for id in var.lb_controller_protected_sg_ids :
    "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/${id}"
  ]
  lb_has_protected_sgs = length(var.lb_controller_protected_sg_ids) > 0
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${local.name_prefix}-lb-controller-policy"
  description = "AWS Load Balancer Controller permissions (upstream policy, controller ${var.lb_controller_version})."
  policy      = file(local.lb_controller_policy_file)

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-lb-controller-policy"
  })
}

data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-lb-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ---------------------------------------------------------------------------
# Guardrail: the upstream policy grants ec2:AuthorizeSecurityGroupIngress /
# Revoke* on Resource "*" (needed for SGs the controller did not create). An
# explicit Deny on the data-tier SGs (RDS, node, cluster) overrides that Allow,
# so a compromised controller pod cannot open 3306 on the RDS SG or widen the
# node SG — preserving the "RDS SG accepts the node SG only" rule (CLAUDE.md #3).
# Enabled only when protected SG IDs are supplied by the environment.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lb_controller_guardrail" {
  count = local.lb_has_protected_sgs ? 1 : 0

  statement {
    sid    = "DenySGMutationOnProtectedGroups"
    effect = "Deny"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DeleteSecurityGroup",
    ]
    resources = local.lb_protected_sg_arns
  }
}

resource "aws_iam_policy" "lb_controller_guardrail" {
  count = local.lb_has_protected_sgs ? 1 : 0

  name        = "${local.name_prefix}-lb-controller-guardrail"
  description = "Explicit Deny preventing the LB controller from mutating the data-tier security groups."
  policy      = data.aws_iam_policy_document.lb_controller_guardrail[0].json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-lb-controller-guardrail"
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller_guardrail" {
  count = local.lb_has_protected_sgs ? 1 : 0

  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller_guardrail[0].arn
}
