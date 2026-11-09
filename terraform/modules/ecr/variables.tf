# Input variables for the ecr module.

variable "project" {
  description = "Project name used for repository namespacing and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Repos are namespaced petclinic-{env}/{service}."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

variable "service_names" {
  description = "Service names; one ECR repository is created per name under petclinic-{env}/."
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0
    error_message = "service_names must contain at least one service."
  }

  validation {
    condition     = alltrue([for s in var.service_names : can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", s))])
    error_message = "each service name must be lowercase alphanumerics separated by '.', '_', or '-' (valid ECR repo path component)."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability for all repos. MUTABLE for dev (re-push during development), IMMUTABLE for prod (deployed tags cannot be overwritten). Defaults to the safer IMMUTABLE."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image vulnerability scanning on push."
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type for repositories. AES256 (SSE-S3-style, AWS-managed) per the technical spec. KMS is not supported here — add a kms_key variable first if a customer-managed key is required."
  type        = string
  default     = "AES256"

  validation {
    condition     = var.encryption_type == "AES256"
    error_message = "encryption_type must be AES256 (KMS is not wired up in this module)."
  }
}

variable "max_image_count" {
  description = "Lifecycle policy: number of images to retain before expiring the oldest."
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count >= 1
    error_message = "max_image_count must be at least 1."
  }
}

variable "untagged_expire_days" {
  description = "Lifecycle policy: expire untagged images older than this many days."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expire_days >= 1
    error_message = "untagged_expire_days must be at least 1."
  }
}

variable "force_delete" {
  description = "Allow Terraform to delete a repository that still contains images (useful for dev teardown)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto all repositories."
  type        = map(string)
  default     = {}
}
