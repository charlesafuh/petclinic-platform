# Input variables for the vpc module.

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Drives resource naming (petclinic-{env}-*) and the EKS cluster subnet tag."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g., 10.0.0.0/16 for dev, 10.1.0.0/16 for prod)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets. Must be the same length as availability_zones (one subnet per AZ)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "public_subnet_cidrs must contain at least 2 CIDRs (2 AZs required for EKS and ALB)."
  }
}

variable "availability_zones" {
  description = "Availability zones for the public subnets. Must be the same length as public_subnet_cidrs."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "availability_zones must contain at least 2 AZs."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources created by this module (in addition to provider default_tags)."
  type        = map(string)
  default     = {}
}
