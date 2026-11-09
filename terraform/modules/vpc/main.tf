# Module: vpc
#
# All-public subnet design — no NAT Gateway, no private subnets, no VPC
# endpoints. Security groups are the primary access control boundary.
# See docs/adr/0001-public-subnets.md (ADR-0001).
#
# Provisions:
#   - VPC (DNS support + hostnames)
#   - 2 public subnets across 2 AZs (map_public_ip_on_launch = true)
#   - Internet Gateway + single public route table (0.0.0.0/0 -> IGW)
#   - 4 baseline security groups: EKS cluster, EKS node, RDS, ALB
#
# Base tags (Project, Environment, ManagedBy) are applied via the provider
# default_tags block in the environment root module.

locals {
  name_prefix = "${var.project}-${var.environment}"

  # EKS requires these tags on subnets for cluster association and ALB
  # subnet auto-discovery by the AWS Load Balancer Controller.
  eks_subnet_tags = {
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
    # Karpenter subnet auto-discovery (EC2NodeClass subnetSelectorTerms).
    "karpenter.sh/discovery" = local.name_prefix
  }

  # NodePort range used by EKS worker nodes for Service type NodePort /
  # ALB target registration.
  nodeport_from = 30000
  nodeport_to   = 32767
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Public subnets (one per AZ)
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, local.eks_subnet_tags, {
    Name = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway + public route table
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ===========================================================================
# Security Groups (baseline — PETPLAT-8)
#
# Rules are defined as separate aws_vpc_security_group_(ingress|egress)_rule
# resources to avoid dependency cycles between SGs that reference each other
# (cluster<->node, node<->alb, node->rds).
# ===========================================================================

# --- EKS cluster (control plane) SG ----------------------------------------
resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane: API server access from worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node_443" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "HTTPS API server access from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "${local.name_prefix}-cluster-ingress-443-from-node" }
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.name_prefix}-cluster-egress-all" }
}

# --- EKS node (worker) SG ---------------------------------------------------
resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker nodes: control plane, inter-node, and ALB traffic"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name                                         = "${local.name_prefix}-eks-node-sg"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
    # Karpenter security-group auto-discovery (EC2NodeClass securityGroupSelectorTerms).
    "karpenter.sh/discovery" = local.name_prefix
  })
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_all" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from the EKS control plane"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_cluster.id

  tags = { Name = "${local.name_prefix}-node-ingress-all-from-cluster" }
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_kubelet" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Kubelet API from the EKS control plane"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.eks_cluster.id

  tags = { Name = "${local.name_prefix}-node-ingress-kubelet-from-cluster" }
}

resource "aws_vpc_security_group_ingress_rule" "node_from_node_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication (self-reference)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "${local.name_prefix}-node-ingress-all-from-self" }
}

resource "aws_vpc_security_group_ingress_rule" "node_from_alb_nodeport" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort services from ALB"
  ip_protocol                  = "tcp"
  from_port                    = local.nodeport_from
  to_port                      = local.nodeport_to
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "${local.name_prefix}-node-ingress-nodeport-from-alb" }
}

resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound (ECR, S3, Secrets Manager, etc. via IGW)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.name_prefix}-node-egress-all" }
}

# --- RDS SG -----------------------------------------------------------------
# MySQL reachable ONLY from EKS worker nodes. Never 0.0.0.0/0.
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL: port 3306 from EKS worker nodes only"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_node_3306" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EKS worker nodes only"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "${local.name_prefix}-rds-ingress-3306-from-node" }
}

# --- ALB SG -----------------------------------------------------------------
# Internet-facing: 80/443 from the world; forwards to node NodePort range.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public ALB: HTTP/HTTPS from internet, forward to EKS nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.name_prefix}-alb-ingress-80" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.name_prefix}-alb-ingress-443" }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_node_nodeport" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to NodePort services on EKS nodes"
  ip_protocol                  = "tcp"
  from_port                    = local.nodeport_from
  to_port                      = local.nodeport_to
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "${local.name_prefix}-alb-egress-nodeport-to-node" }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_node_healthcheck" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Health checks to EKS nodes on 8080"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "${local.name_prefix}-alb-egress-healthcheck-to-node" }
}
