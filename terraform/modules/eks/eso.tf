# ===========================================================================
# IRSA role for the External Secrets Operator (PETPLAT-37)
#
# ESO runs as ServiceAccount external-secrets-sa in the external-secrets
# namespace and reads application secrets from AWS Secrets Manager, syncing
# them into Kubernetes Secrets (PETPLAT-34/35/36). The trust policy scopes
# sts:AssumeRoleWithWebIdentity to exactly that ServiceAccount via the cluster
# OIDC provider; the permissions policy grants read-only Secrets Manager access
# scoped to this environment's secret namespace (petclinic/{env}/*) only —
# least privilege per CLAUDE.md #5, tighter than a cross-environment grant.
#
# data.aws_caller_identity.current is declared in lb-controller.tf (same module).
# ===========================================================================

locals {
  # Secrets Manager ARNs this role may read. Scoped to this environment's secret
  # path; the trailing "*" covers the 6-character suffix AWS appends to secret
  # ARNs, and "/*" covers nested paths like .../config-server/git-username.
  eso_secret_arns = [
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/${var.environment}/*",
  ]

  eso_has_custom_kms = length(var.eso_kms_key_arns) > 0
}

data "aws_iam_policy_document" "eso_assume" {
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
      values   = ["system:serviceaccount:${var.eso_namespace}:${var.eso_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name_prefix}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eso-role"
  })
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid    = "ReadPetclinicSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = local.eso_secret_arns
  }

  # kms:Decrypt is only required when secrets are encrypted with a customer-managed
  # KMS key. The project uses the AWS-managed aws/secretsmanager key, whose key
  # policy already grants Secrets Manager the decrypt, so this statement is added
  # only when custom key ARNs are supplied.
  dynamic "statement" {
    for_each = local.eso_has_custom_kms ? [1] : []
    content {
      sid       = "DecryptCustomKmsKeys"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.eso_kms_key_arns
    }
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${local.name_prefix}-eso-policy"
  description = "Read-only Secrets Manager access for the External Secrets Operator (petclinic/${var.environment}/* only)."
  policy      = data.aws_iam_policy_document.eso.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eso-policy"
  })
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}
