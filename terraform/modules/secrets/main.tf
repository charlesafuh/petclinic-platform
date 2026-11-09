# Module: secrets (PETPLAT-33)
#
# Non-RDS application secrets in AWS Secrets Manager. RDS master credentials are
# owned by the rds module (PETPLAT-23) and are NOT duplicated here.
#
# Secrets managed here:
#   - petclinic/{env}/openai-api-key                  (GenAI service, plaintext)
#   - petclinic/{env}/config-server/git-username      (optional)
#   - petclinic/{env}/config-server/git-password      (optional)
#
# All values arrive as sensitive variables — nothing is hardcoded. Secret values
# never appear in plan/apply output (the variables and secret_string are marked
# sensitive). Each secret is encrypted with the default AWS-managed KMS key
# (aws/secretsmanager). The External Secrets Operator reads these via the ESO
# IRSA role (petclinic-{env}-eso-role, PETPLAT-37) and syncs them into
# Kubernetes Secrets (PETPLAT-35/36).
#
# Base tags (Project, Environment, ManagedBy) come from the provider
# default_tags block in the environment root module.

locals {
  secret_prefix = "${var.project}/${var.environment}"

  openai_secret_name       = "${local.secret_prefix}/openai-api-key"
  git_username_secret_name = "${local.secret_prefix}/config-server/git-username"
  git_password_secret_name = "${local.secret_prefix}/config-server/git-password"

  # nonsensitive() reduces the "is it empty" check to a plain bool so it can
  # drive count. Terraform >= 1.6.x historically rejected a sensitive-derived
  # value as a count argument; current versions allow it, but wrapping here keeps
  # plans working across the whole >= 1.6.0 range the repo pins. Only the one bit
  # (value empty or not) is revealed — which resource presence already exposes.
  create_openai_version = nonsensitive(var.openai_api_key != "")
  create_git_username   = nonsensitive(var.config_server_git_username != "")
  create_git_password   = nonsensitive(var.config_server_git_password != "")
}

# --- OpenAI API key ---------------------------------------------------------
resource "aws_secretsmanager_secret" "openai" {
  name                    = local.openai_secret_name
  description             = "OpenAI API key for the ${var.project}-${var.environment} GenAI service."
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, {
    Name = local.openai_secret_name
  })
}

# Only create a version once a value is supplied, so an empty default does not
# push a blank secret. The real key is injected via TF_VAR_openai_api_key.
resource "aws_secretsmanager_secret_version" "openai" {
  count         = local.create_openai_version ? 1 : 0
  secret_id     = aws_secretsmanager_secret.openai.id
  secret_string = var.openai_api_key
}

# --- Optional Config Server Git credentials ---------------------------------
resource "aws_secretsmanager_secret" "git_username" {
  count                   = local.create_git_username ? 1 : 0
  name                    = local.git_username_secret_name
  description             = "Git username for the ${var.project}-${var.environment} Config Server backing repo."
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, {
    Name = local.git_username_secret_name
  })
}

resource "aws_secretsmanager_secret_version" "git_username" {
  count         = local.create_git_username ? 1 : 0
  secret_id     = aws_secretsmanager_secret.git_username[0].id
  secret_string = var.config_server_git_username
}

resource "aws_secretsmanager_secret" "git_password" {
  count                   = local.create_git_password ? 1 : 0
  name                    = local.git_password_secret_name
  description             = "Git password/token for the ${var.project}-${var.environment} Config Server backing repo."
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, {
    Name = local.git_password_secret_name
  })
}

resource "aws_secretsmanager_secret_version" "git_password" {
  count         = local.create_git_password ? 1 : 0
  secret_id     = aws_secretsmanager_secret.git_password[0].id
  secret_string = var.config_server_git_password
}
