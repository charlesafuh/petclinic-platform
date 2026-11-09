variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment. Drives resource naming (petclinic-{env}-*) and the Environment tag."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "petclinic"
}

# --- Networking (VPC) -------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the dev public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the dev public subnets."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

# --- EKS --------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version for the dev EKS cluster."
  type        = string
  default     = "1.37"
}

variable "node_instance_types" {
  description = "Instance types for the dev EKS node group (Graviton t4g)."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_min_size" {
  description = "Minimum worker nodes (dev)."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker nodes (dev)."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired worker nodes (dev)."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root EBS volume size (GB) per node (dev)."
  type        = number
  default     = 20
}

# --- RDS --------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class (dev)."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial RDS storage in GB (dev)."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Max RDS autoscale storage in GB (dev). Equal to allocated_storage disables autoscaling."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ (dev)."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "RDS automated backup retention in days (dev)."
  type        = number
  default     = 7
}

variable "db_skip_final_snapshot" {
  description = "Skip the RDS final snapshot on destroy (dev)."
  type        = bool
  default     = true
}

# --- DNS & Ingress ----------------------------------------------------------

variable "domain_name" {
  description = "Registered apex domain with an existing public Route 53 hosted zone (e.g. example.com). Leave empty to disable the DNS module; set it to your real domain to request the ACM certificate and create the alias record."
  type        = string
  default     = "ngohnwei.com"
}

variable "dns_record_name" {
  description = "Subdomain label for the dev app record: petclinic-dev.{domain_name}."
  type        = string
  default     = "petclinic-dev"
}

variable "enable_dns_alias" {
  description = "Create the Route 53 alias records -> ALB. Now that the Ingress has provisioned the ALB (phase 2 complete), this defaults to true so routine `terraform apply` runs keep the records instead of destroying them. The records are resolved via data.aws_lb by name."
  type        = bool
  default     = true
}

variable "alb_name" {
  description = "Name of the ALB the Ingress provisions (alb.ingress.kubernetes.io/load-balancer-name annotation), e.g. petclinic-dev-alb. Used with enable_dns_alias."
  type        = string
  default     = "petclinic-dev-alb"
}

# --- Secrets ----------------------------------------------------------------

variable "openai_api_key" {
  description = "OpenAI API key for the GenAI service, stored at petclinic/dev/openai-api-key. SENSITIVE — never hardcode or commit it; supply via TF_VAR_openai_api_key or a gitignored *.tfvars. Empty creates the secret without a version."
  type        = string
  default     = ""
  sensitive   = true
}

# --- ECR --------------------------------------------------------------------

variable "service_names" {
  description = "Microservice names; one ECR repository is created per name."
  type        = list(string)
  default = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]
}

# --- Cost / Budgets ---------------------------------------------------------

variable "budget_alert_email" {
  description = "Email address that receives AWS Budget alerts at 50/80/100% of the monthly budget."
  type        = string
}
