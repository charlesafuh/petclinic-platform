# Module: eks
#
# EKS cluster (public endpoint, all-public subnets — see ADR-0001), OIDC
# provider for IRSA, a Graviton managed node group, EKS access entries for
# cluster administrators, and pinned managed add-ons (coredns, kube-proxy,
# vpc-cni, aws-ebs-csi-driver).
#
# Base tags (Project, Environment, ManagedBy) come from the provider
# default_tags block in the environment root module.

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix

  # OIDC issuer URL (https://oidc.eks.<region>.amazonaws.com/id/XXXX) and the
  # same value without the scheme, used to build IRSA trust-policy conditions.
  oidc_issuer_url  = aws_eks_cluster.main.identity[0].oidc[0].issuer
  oidc_issuer_host = replace(local.oidc_issuer_url, "https://", "")

  node_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]
}

# ===========================================================================
# Cluster IAM role (PETPLAT-12)
# ===========================================================================
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ===========================================================================
# KMS key for Kubernetes Secrets envelope encryption + control-plane log group
# ===========================================================================
resource "aws_kms_key" "eks" {
  description             = "${local.name_prefix} EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-secrets"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.name_prefix}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# Pre-create the control-plane log group so logs have a bounded retention
# (EKS otherwise auto-creates it with "never expire").
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-logs"
  })
}

# ===========================================================================
# EKS cluster (PETPLAT-12)
# ===========================================================================
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Cluster admin access is managed explicitly via aws_eks_access_entry
    # (cluster_admin_principal_arns), not the implicit creator bootstrap,
    # to keep access fully reproducible in Terraform and avoid a duplicate
    # entry when the creator is also listed.
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Envelope-encrypt Kubernetes Secrets with a customer-managed KMS key.
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(var.tags, {
    Name = local.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ===========================================================================
# OIDC provider for IRSA (PETPLAT-12)
# ===========================================================================
data "tls_certificate" "oidc" {
  url = local.oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = local.oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-oidc"
  })
}

# ===========================================================================
# Node IAM role (PETPLAT-13)
# ===========================================================================
data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(local.node_managed_policy_arns)
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ===========================================================================
# Launch template for the node group (PETPLAT-13)
# Attaches the custom node SG + the EKS-managed primary cluster SG, encrypts
# the root volume, and enforces IMDSv2.
# ===========================================================================
resource "aws_launch_template" "node" {
  name_prefix = "${local.name_prefix}-node-"

  vpc_security_group_ids = [
    var.node_sg_id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
  ]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 required; hop limit 1 prevents non-host-network pods from reaching
  # the instance metadata service (forces IRSA for pod AWS access).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-node-vol"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-node-lt"
  })
}

# ===========================================================================
# Managed node group (PETPLAT-13)
# ===========================================================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    environment  = var.environment
    "managed-by" = "terraform"
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nodes"
  })

  # desired_size drifts as the cluster autoscales; ignore it after creation.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ===========================================================================
# EKS access entries for cluster administrators (PETPLAT-14)
# ===========================================================================
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-access-${substr(sha1(each.value), 0, 8)}"
  })
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# ===========================================================================
# IRSA role for the EBS CSI Driver (PETPLAT-84)
# ===========================================================================
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ===========================================================================
# Managed add-ons (PETPLAT-84) — pinned versions, OVERWRITE on conflict
# ===========================================================================
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = var.addon_version_kube_proxy
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Name = "${local.name_prefix}-kube-proxy" })
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_version_vpc_cni
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Name = "${local.name_prefix}-vpc-cni" })
}

# CoreDNS runs as pods, so it needs nodes to be available first.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = var.addon_version_coredns
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Name = "${local.name_prefix}-coredns" })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_version_ebs_csi
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Name = "${local.name_prefix}-ebs-csi-driver" })

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
