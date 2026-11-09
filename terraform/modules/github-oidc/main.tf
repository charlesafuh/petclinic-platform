# Module: github-oidc (PETPLAT-52)
#
# OIDC federation between GitHub Actions (application repo) and AWS, so the CI
# build workflow can push images to ECR WITHOUT long-lived AWS access keys.
#
# Two resources:
#   1. aws_iam_openid_connect_provider for token.actions.githubusercontent.com
#      (account-global; can be reused via create_oidc_provider = false).
#   2. aws_iam_role assumed via sts:AssumeRoleWithWebIdentity, trust-scoped to
#      exactly repo:{owner}/{repo}:ref:refs/heads/{branch} of the APP repo, with
#      an ECR-push-only permissions policy (no ecr:*, no "*").
#
# Base tags (Project, Environment, ManagedBy) come from the provider
# default_tags block in the environment root module.

data "aws_caller_identity" "current" {}

locals {
  oidc_url  = "https://token.actions.githubusercontent.com"
  oidc_host = "token.actions.githubusercontent.com"

  # Trust subject: only this branch of the application repo fork may assume the
  # role. The build workflow runs in the app repo context, so this is the app
  # repo (not the platform repo) and not a wildcard.
  oidc_subject = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"

  # Resolve the OIDC provider ARN whether we create it or reuse an existing one.
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # ECR repositories the role may push to. Prefer explicit ARNs; otherwise scope
  # to the petclinic-{env} namespaces in this account/region. Each ARN ends in
  # /* so it matches every service repo under the namespace (e.g.
  # repository/petclinic-dev/customers-service) but nothing outside it.
  ecr_resource_arns = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : [
    for ns in var.ecr_repository_namespaces :
    "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${ns}/*"
  ]
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider. Thumbprint is computed from the live issuer certificate
# (AWS no longer validates it for this provider, but the argument is still
# accepted and this avoids hardcoding a fingerprint that can rotate).
# ---------------------------------------------------------------------------
data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = local.oidc_url
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.oidc_url
  client_id_list  = [var.oidc_audience]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name = "${var.project}-github-oidc"
  })
}

# ---------------------------------------------------------------------------
# Trust policy: sts:AssumeRoleWithWebIdentity, federated to the GitHub provider,
# constrained to the expected audience AND the app-repo/main subject.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "GitHubActionsAssumeWithOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Audience must match what configure-aws-credentials requests.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [var.oidc_audience]
    }

    # Subject must be exactly the app repo's main branch — not another repo,
    # not another branch, not a pull_request / tag / environment subject.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.oidc_subject]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  description          = "GitHub Actions CI (OIDC) - pushes petclinic images to ECR. Trusts ${local.oidc_subject}."
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600

  tags = merge(var.tags, {
    Name = var.role_name
  })
}

# ---------------------------------------------------------------------------
# Permissions: ECR push only. Least privilege per CLAUDE.md #5 — specific
# actions, specific resources. GetAuthorizationToken is a separate statement
# because it does not support resource-level permissions (must be "*").
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # AWS does not allow resource scoping on this action.
  }

  statement {
    sid    = "EcrPushToPetclinicRepos"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = local.ecr_resource_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.role_name}-ecr-push"
  description = "ECR push-only permissions for the GitHub Actions CI role (scoped to petclinic repositories)."
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = merge(var.tags, {
    Name = "${var.role_name}-ecr-push"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
