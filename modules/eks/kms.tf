# Customer-managed key for envelope encryption of Kubernetes Secrets in etcd.
# Once a cluster has secrets encryption enabled it cannot be turned off, and
# deleting this key makes every Secret in the cluster unreadable.
resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption for ${var.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-secrets"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# EKS creates this group on its own (with no retention) the first time logging
# is enabled. Managing it here sets retention and keeps destroy clean.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
