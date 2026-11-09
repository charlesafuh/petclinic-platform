# Module: rds
#
# MySQL 8.0 instance for the Spring Petclinic domain services (customers, visits,
# vets). A single shared `petclinic` database backs all three (cross-service FK:
# visits.pet_id -> pets.id). Master credentials are generated with random_password
# and stored as a JSON secret in Secrets Manager (petclinic/{env}/rds-credentials)
# for External Secrets Operator to sync into Kubernetes later.
#
# Base tags (Project, Environment, ManagedBy) come from the provider default_tags
# block in the environment root module. The RDS security group (3306 from the EKS
# node SG only) is created by the VPC module and passed in as security_group_id.

locals {
  identifier  = "${var.project}-${var.environment}-mysql"
  secret_name = "${var.project}/${var.environment}/rds-credentials"

  # Parameter group family from the major.minor of the engine version
  # ("8.0" -> mysql8.0, "8.4" -> mysql8.4, "8.0.35" -> mysql8.0). Overridable.
  parameter_group_family = coalesce(
    var.parameter_group_family,
    "mysql${join(".", slice(split(".", var.engine_version), 0, 2))}"
  )

  # Autoscaling requires max > allocated; equal values (default 20/20) disable it.
  effective_max_storage = var.max_allocated_storage > var.allocated_storage ? var.max_allocated_storage : null

  # Only meaningful when skip_final_snapshot = false. A random suffix keeps the
  # name unique across destroy/recreate cycles (AWS rejects duplicate snapshot IDs).
  final_snapshot_name = coalesce(
    var.final_snapshot_identifier,
    "${local.identifier}-final-${random_id.final_snapshot.hex}"
  )
}

# Unique suffix for the final snapshot identifier (avoids collisions on recreate).
resource "random_id" "final_snapshot" {
  byte_length = 4
}

# --- Master password --------------------------------------------------------
# 20 chars with mixed classes. override_special excludes characters RDS rejects
# in a MySQL master password ('/', '@', '"', and space).
resource "random_password" "master" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()-_=+[]{}:?."
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# --- Networking -------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${local.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${local.identifier}-subnet-group"
  })
}

# --- Parameter group (utf8mb4) ----------------------------------------------
resource "aws_db_parameter_group" "this" {
  # name_prefix keeps the group name unique per replacement, so a family change
  # (which forces replacement) can create-before-destroy without a name clash.
  name_prefix = "${local.identifier}-params-"
  family      = local.parameter_group_family

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = merge(var.tags, {
    Name = "${local.identifier}-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Instance ---------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier = local.identifier

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = local.effective_max_storage
  storage_type          = var.storage_type
  storage_encrypted     = true # AWS-managed default KMS key (aws/rds)

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result
  port     = 3306

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period
  copy_tags_to_snapshot   = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : local.final_snapshot_name
  deletion_protection       = var.deletion_protection

  auto_minor_version_upgrade = true
  apply_immediately          = false

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = merge(var.tags, {
    Name = local.identifier
  })

  lifecycle {
    precondition {
      condition     = var.max_allocated_storage == var.allocated_storage || var.max_allocated_storage > var.allocated_storage
      error_message = "max_allocated_storage must be >= allocated_storage (equal disables autoscaling; greater enables it)."
    }
  }
}

# --- Credentials in Secrets Manager ----------------------------------------
# Single JSON secret { "username": ..., "password": ... } at
# petclinic/{env}/rds-credentials. The password never appears in Terraform
# output; random_password.result and the secret_string are sensitive by design.
resource "aws_secretsmanager_secret" "rds" {
  name                    = local.secret_name
  description             = "RDS master credentials for ${local.identifier} (MySQL)."
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, {
    Name = local.secret_name
  })
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}
