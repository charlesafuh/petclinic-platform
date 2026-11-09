# Dev environment root module.
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
# CIDR: 10.0.0.0/16 (dev). See docs/adr/0001-public-subnets.md.
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
# Cluster: petclinic-dev, Kubernetes 1.37, 2x t4g.small (ARM).
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
# ECR (E-4) — one private repo per service under petclinic-dev/.
# Dev uses MUTABLE tags (re-push during development) and force_delete so the
# environment can be torn down cleanly between sessions.
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  project       = var.project
  environment   = var.environment
  service_names = var.service_names

  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# ---------------------------------------------------------------------------
# RDS (E-5) — MySQL 8.0 for the domain services (customers/visits/vets).
# Single shared `petclinic` DB, db.t4g.micro, single-AZ. Credentials generated
# and stored at petclinic/dev/rds-credentials in Secrets Manager.
# Dev: 7-day backups, skip final snapshot on teardown.
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
}

# ---------------------------------------------------------------------------
# DNS & Ingress (E-6) — Route 53 (looked up) + wildcard ACM cert for the
# API Gateway. Enabled only once a real registered domain is set in
# var.domain_name (left empty by default so plan/apply is a no-op until then).
# The alias A record -> ALB is created in a second apply with the ALB values;
# see terraform/modules/dns/README.md.
# ---------------------------------------------------------------------------
module "dns" {
  count  = var.domain_name != "" ? 1 : 0
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name
  record_name = var.dns_record_name

  # Cover the apex too (CN stays *.{domain}; apex added as a SAN) so HTTPS is
  # valid for the bare domain, and publish an apex alias -> the same ALB. Dev
  # owns the apex record.
  subject_alternative_names = [var.domain_name]
  create_apex_alias         = true

  # Phase 2: flip enable_dns_alias to true after the Ingress provisions the ALB
  # (named via the Ingress load-balancer-name annotation). The record is then
  # resolved from data.aws_lb, so routine applies never drop it.
  enable_alias = var.enable_dns_alias
  alb_name     = var.alb_name
}

# ---------------------------------------------------------------------------
# Secrets (E-7) — non-RDS application secrets in Secrets Manager. Currently the
# GenAI service's OpenAI API key at petclinic/dev/openai-api-key. The value is a
# sensitive variable supplied via TF_VAR_openai_api_key (never committed); leave
# it empty to create the secret container and set the value in a later apply.
# RDS credentials are owned by the rds module above. The ESO IRSA role that
# reads these is in the eks module (petclinic-dev-eso-role).
# ---------------------------------------------------------------------------
module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment

  openai_api_key = var.openai_api_key
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
