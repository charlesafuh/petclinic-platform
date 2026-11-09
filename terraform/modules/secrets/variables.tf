# Input variables for the secrets module (PETPLAT-33).

variable "project" {
  description = "Project name used for resource naming and the secret path (petclinic/{env}/...)."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Drives the secret path (petclinic/{env}/...)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

# --- OpenAI API key (petclinic/{env}/openai-api-key) ------------------------

variable "openai_api_key" {
  description = <<-EOT
    OpenAI API key for the GenAI service, stored as a plaintext secret at
    petclinic/{env}/openai-api-key. SENSITIVE — never hardcode or commit it.
    Supply it at apply time via the TF_VAR_openai_api_key environment variable
    or a gitignored *.tfvars file. Leave empty to create the secret container
    without a version (set the value later via a subsequent apply or the
    console); External Secrets will sync it once a version exists.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

# --- Optional Config Server Git credentials ---------------------------------
# Only created when a non-empty value is supplied (the Config Server reads its
# configuration from a public Git repo by default, so these are usually unset).

variable "config_server_git_username" {
  description = "Optional Git username for a private Config Server backing repo (petclinic/{env}/config-server/git-username). Empty disables this secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "config_server_git_password" {
  description = "Optional Git password/token for a private Config Server backing repo (petclinic/{env}/config-server/git-password). Empty disables this secret."
  type        = string
  default     = ""
  sensitive   = true
}

# --- Lifecycle --------------------------------------------------------------

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window (days) after deletion. 0 forces immediate deletion so the secret name can be reused after teardown (dev); set 7-30 in real production."
  type        = number
  default     = 0

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days must be 0, or between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
