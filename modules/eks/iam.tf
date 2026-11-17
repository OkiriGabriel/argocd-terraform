data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}

################################################################################
# Control plane role
################################################################################

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster"
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Lets the control plane use the KMS key for Kubernetes Secrets envelope encryption.
resource "aws_iam_role_policy" "cluster_kms" {
  name = "secrets-encryption"
  role = aws_iam_role.cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ListGrants",
        "kms:DescribeKey",
      ]
      Resource = aws_kms_key.eks.arn
    }]
  })
}

################################################################################
# Node role
################################################################################

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node"
  })
}

locals {
  # AmazonEKS_CNI_Policy is intentionally NOT attached to the node role. The
  # VPC CNI gets its own IRSA role below, so ordinary pods cannot borrow
  # network-management permissions through the node's instance profile.
  node_policy_arns = merge(
    {
      worker = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
      ecr    = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
    },
    var.enable_ssm ? { ssm = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore" } : {},
  )
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_policy_arns

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

################################################################################
# IRSA: OIDC provider and VPC CNI role
################################################################################

resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-irsa"
  })
}

locals {
  oidc_issuer = trimprefix(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://")
}

resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRoleWithWebIdentity"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.this.arn }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-node"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpc-cni"
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Migration aid only. Clusters built from the old module had AmazonEKS_CNI_Policy
# on the node role, and the running aws-node pods depend on it until the VPC CNI
# add-on is switched to its IRSA role. Set legacy_node_cni_policy = true for the
# first apply of an existing cluster, then set it back to false. See MIGRATION.md.
resource "aws_iam_role_policy_attachment" "node_cni_legacy" {
  count = var.legacy_node_cni_policy ? 1 : 0

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}
