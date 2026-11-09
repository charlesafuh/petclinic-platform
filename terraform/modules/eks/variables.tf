# Input variables for the eks module.

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Drives resource naming (petclinic-{env}-*)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either 'dev' or 'prod'."
  }
}

variable "region" {
  description = "AWS region (used to build the kubeconfig update command output)."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.37"
}

variable "subnet_ids" {
  description = "Subnet IDs for the cluster and node group (public subnets in this design)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least 2 subnets across 2 AZs."
  }
}

variable "cluster_sg_id" {
  description = "Additional security group ID to attach to the EKS control plane ENIs."
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID to attach to the EKS worker nodes (via launch template)."
  type        = string
}

# --- Managed node group -----------------------------------------------------

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the node group. AL2023_ARM_64_STANDARD for Graviton (t4g) nodes — Amazon Linux 2 (AL2_ARM_64) is only supported on EKS <= 1.32."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_capacity_type" {
  description = "Capacity type for the node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root EBS volume size (GB) for each node. 20 GB fits within the 30 GB EBS free tier."
  type        = number
  default     = 20
}

# --- Control-plane logging --------------------------------------------------

variable "cluster_log_retention_days" {
  description = "Retention (days) for the EKS control-plane CloudWatch log group."
  type        = number
  default     = 14
}

# --- API server endpoint access --------------------------------------------

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API server endpoint. Restrict to office/VPN ranges in real production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Cluster access (PETPLAT-14) --------------------------------------------

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs (users/roles) granted cluster-admin via EKS access entries. The deploying principal should be included so kubectl works after apply."
  type        = list(string)
  default     = []
}

# --- Managed add-on versions (PETPLAT-84) -----------------------------------
# Versions are pinned (never 'latest') for reproducibility. To upgrade, run:
#   aws eks describe-addon-versions --kubernetes-version <ver> --addon-name <addon>
# pick the target addonVersion, bump the default here, then plan/apply.

variable "addon_version_coredns" {
  description = "Pinned version of the CoreDNS managed add-on (EKS 1.37 default)."
  type        = string
  default     = "v1.14.7-eksbuild.22"
}

variable "addon_version_kube_proxy" {
  description = "Pinned version of the kube-proxy managed add-on (EKS 1.37 default)."
  type        = string
  default     = "v1.37.0-eksbuild.32"
}

variable "addon_version_vpc_cni" {
  description = "Pinned version of the Amazon VPC CNI managed add-on (EKS 1.37 default)."
  type        = string
  default     = "v1.22.4-eksbuild.10"
}

variable "addon_version_ebs_csi" {
  description = "Pinned version of the AWS EBS CSI Driver managed add-on (EKS 1.37 default)."
  type        = string
  default     = "v1.67.2-eksbuild.1"
}

variable "lb_controller_version" {
  description = "AWS Load Balancer Controller appVersion. Selects the IAM policy file lb-controller-iam-policy-{version}.json and is used as the install image tag. Keep in sync with scripts/install-lb-controller.sh."
  type        = string
  default     = "v3.6.2"
}

variable "lb_controller_protected_sg_ids" {
  description = "Security group IDs the LB controller must never mutate (e.g. RDS, node, cluster SGs). An explicit Deny is attached to the controller role for these. Empty disables the guardrail."
  type        = list(string)
  default     = []
}

# --- External Secrets Operator IRSA (PETPLAT-37) ----------------------------

variable "eso_namespace" {
  description = "Kubernetes namespace the External Secrets Operator ServiceAccount lives in (IRSA trust-policy subject)."
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account_name" {
  description = "Name of the ESO ServiceAccount the IRSA role trusts (annotate this SA with the eso_role_arn output)."
  type        = string
  default     = "external-secrets-sa"
}

variable "eso_kms_key_arns" {
  description = "Customer-managed KMS key ARNs whose secrets ESO must decrypt. Leave empty when secrets use the AWS-managed aws/secretsmanager key (the default) — no kms:Decrypt statement is then added."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.eso_kms_key_arns : can(regex("^arn:aws:kms:", a))])
    error_message = "Each eso_kms_key_arns entry must be a KMS key ARN starting with 'arn:aws:kms:'."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources created by this module."
  type        = map(string)
  default     = {}
}
