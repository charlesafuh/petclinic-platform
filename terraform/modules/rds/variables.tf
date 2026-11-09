# Input variables for the rds module.

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Drives naming (petclinic-{env}-mysql) and the secret path (petclinic/{env}/rds-credentials)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

# --- Networking -------------------------------------------------------------

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. Must span at least two AZs (RDS requirement)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets in different AZs."
  }
}

variable "security_group_id" {
  description = "RDS security group ID (allows 3306 from the EKS node SG only). Comes from the VPC module."
  type        = string
}

# --- Engine / instance ------------------------------------------------------

variable "engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "parameter_group_family" {
  description = "DB parameter group family. Defaults to mysql{major}.{minor} derived from engine_version; override for non-standard versions."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "RDS instance class. Default db.t4g.micro (free-tier eligible, ARM/Graviton)."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GB."
  }
}

variable "max_allocated_storage" {
  description = "Maximum storage (GB) for RDS storage autoscaling. Autoscaling is enabled only when this exceeds allocated_storage; equal values (the default 20/20) disable it."
  type        = number
  default     = 20
}

variable "storage_type" {
  description = "EBS storage type for the DB volume."
  type        = string
  default     = "gp2"
}

# --- Credentials ------------------------------------------------------------

variable "master_username" {
  description = "RDS master username. Stored alongside the generated password in Secrets Manager."
  type        = string
  default     = "petclinic"
}

variable "database_name" {
  description = "Name of the initial database created on the instance. All three domain services share this one database."
  type        = string
  default     = "petclinic"
}

# --- High availability / backups / lifecycle -------------------------------

variable "multi_az" {
  description = "Enable Multi-AZ deployment. false for both envs (cost optimization for a learning project); enable in real production."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days (7 for dev, 30 for prod)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true for dev, false for prod)."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Name for the final snapshot when skip_final_snapshot is false. Defaults to {identifier}-final when unset."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Enable deletion protection on the instance."
  type        = bool
  default     = false
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window (days) after deletion. 0 forces immediate deletion so the secret name can be reused after teardown (useful for dev); set 7-30 in real production."
  type        = number
  default     = 0

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days must be 0, or between 7 and 30."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  description = "MySQL log types to export to CloudWatch Logs (e.g. [\"error\", \"slowquery\"]). Empty disables export."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
