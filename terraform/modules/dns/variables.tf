# Input variables for the dns module.

variable "project" {
  description = "Project name used for tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

variable "domain_name" {
  description = "Registered apex domain that already has a PUBLIC Route 53 hosted zone (e.g. example.com). The zone is looked up with a data source, never created here — Route 53 creates it on domain registration, and a second zone would break ACM DNS validation."
  type        = string
}

variable "record_name" {
  description = "Subdomain label for this environment's record (e.g. petclinic-dev or petclinic). The app record becomes {record_name}.{domain_name}. Empty uses the apex domain."
  type        = string
  default     = ""
}

variable "certificate_domain" {
  description = "Primary domain for the ACM certificate. Defaults to the wildcard *.{domain_name}, which covers both dev (petclinic-dev.*) and prod (petclinic.*) hostnames."
  type        = string
  default     = null
}

variable "subject_alternative_names" {
  description = "Additional SANs for the ACM certificate (e.g. the apex domain). The wildcard does not cover the apex, so add it here if the apex must be served."
  type        = list(string)
  default     = []
}

variable "enable_alias" {
  description = "Create the alias A record -> ALB. Flip to true (a committed value, not a per-run -var) only after the Ingress has provisioned the ALB, so a plain apply never drops the record. Requires alb_name."
  type        = bool
  default     = false
}

variable "alb_name" {
  description = "Name of the ALB the Ingress provisions, as set by the alb.ingress.kubernetes.io/load-balancer-name annotation (e.g. petclinic-dev-alb). Looked up with data.aws_lb when enable_alias is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_alias || var.alb_name != ""
    error_message = "alb_name must be set when enable_alias is true."
  }
}

variable "tags" {
  description = "Additional tags merged onto taggable resources (ACM certificate)."
  type        = map(string)
  default     = {}
}

variable "create_apex_alias" {
  description = "Also create an apex alias record (domain_name -> ALB) alongside record_fqdn, so the bare domain serves the app. Requires the certificate to cover the apex (subject_alternative_names). Only one environment should own the apex."
  type        = bool
  default     = false
}
