# Prod environment root module.
#
# Module wiring (VPC, EKS, ECR, RDS, DNS, Secrets, Observability) is added in
# later epics (E-2 onward). This file currently exposes identity/region data
# sources that downstream modules and outputs rely on.

data "aws_caller_identity" "current" {}

# Resolve the deploying principal to its underlying IAM role/user ARN
# (issuer_arn), which is what EKS access entries require — a raw
# assumed-role session ARN is rejected.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# ---------------------------------------------------------------------------
# Networking (E-2) — VPC, public subnets, IGW, baseline security groups.
# CIDR: 10.1.0.0/16 (prod, non-overlapping with dev). See ADR-0001.
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
}

# ---------------------------------------------------------------------------
# EKS (E-3) — cluster, OIDC/IRSA, Graviton node group, pinned add-ons.
# Cluster: petclinic-prod, Kubernetes 1.37, 2x t4g.small (ARM).
# ---------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment
  region      = var.aws_region

  cluster_version = var.cluster_version

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  node_disk_size      = var.node_disk_size

  # Keep control-plane logs longer in prod.
  cluster_log_retention_days = 90

  # Grant the deploying principal cluster-admin so kubectl works after apply.
  cluster_admin_principal_arns = [data.aws_iam_session_context.current.issuer_arn]

  # Deny the LB controller from mutating the data-tier security groups.
  # Protect only the data tier. The NODE SG is intentionally NOT listed: the LB
  # controller must add backend-traffic rules to it for target-type:ip Ingresses
  # (ALB -> pod:8080 health checks). Guardrailing it breaks those health checks.
  lb_controller_protected_sg_ids = [
    module.vpc.rds_sg_id,
    module.vpc.eks_cluster_sg_id,
  ]
}

# ---------------------------------------------------------------------------
# ECR (E-4) — one private repo per service under petclinic-prod/.
# Prod uses IMMUTABLE tags so deployed image tags cannot be overwritten, and
# keeps force_delete off to protect images.
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  project       = var.project
  environment   = var.environment
  service_names = var.service_names

  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
}

# ---------------------------------------------------------------------------
# RDS (E-5) — MySQL 8.0 for the domain services (customers/visits/vets).
# Single shared `petclinic` DB, db.t4g.micro, single-AZ (cost optimization;
# enable Multi-AZ for real production). Credentials stored at
# petclinic/prod/rds-credentials in Secrets Manager.
# Prod: 30-day backups, final snapshot taken on destroy.
# ---------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  max_allocated_storage   = var.db_max_allocated_storage
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  skip_final_snapshot     = var.db_skip_final_snapshot

  # Keep deleted credentials recoverable in prod (dev uses the module default of 0
  # so the secret name is immediately reusable after teardown).
  secret_recovery_window_days = 7
}

# ---------------------------------------------------------------------------
# Secrets (E-7) — non-RDS application secrets in Secrets Manager. Currently the
# GenAI service's OpenAI API key at petclinic/prod/openai-api-key. The value is a
# sensitive variable supplied via TF_VAR_openai_api_key (never committed); leave
# it empty to create the secret container and set the value in a later apply.
# RDS credentials are owned by the rds module above. The ESO IRSA role that
# reads these is in the eks module (petclinic-prod-eso-role).
# Prod keeps a 7-day recovery window on deleted secrets (dev uses 0).
# ---------------------------------------------------------------------------
module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment

  openai_api_key = var.openai_api_key

  secret_recovery_window_days = 7
}

# ---------------------------------------------------------------------------
# Karpenter (E-14) — IAM controller role (IRSA), node instance profile, SQS
# interruption queue + EventBridge rules. The controller Helm install and the
# NodePool/EC2NodeClass CRDs live in k8s/base/karpenter/. Inputs come straight
# from the eks module outputs.
# ---------------------------------------------------------------------------
module "karpenter" {
  source = "../../modules/karpenter"

  project     = var.project
  environment = var.environment

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_arn     = module.eks.node_role_arn
}

# ---------------------------------------------------------------------------
# Budget alerts (E-14, PETPLAT-75) — $100/month, email on ACTUAL spend at
# 50% / 80% / 100%. ACTUAL (not FORECASTED) so alerts fire on real charges.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = toset([50, 80, 100])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
}
