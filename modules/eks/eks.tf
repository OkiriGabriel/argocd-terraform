################################################################################
# Control plane
################################################################################

resource "aws_eks_cluster" "this" {
  name                      = var.cluster_name
  role_arn                  = aws_iam_role.cluster.arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = var.cluster_log_types
  deletion_protection       = var.deletion_protection

  vpc_config {
    # Control plane ENIs go in private subnets only. The legacy flag keeps the
    # old public+private list for clusters built by the previous module.
    subnet_ids = var.legacy_control_plane_public_subnets ? concat(aws_subnet.public[*].id, aws_subnet.private[*].id) : aws_subnet.private[*].id

    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  access_config {
    # Access entries only; the aws-auth ConfigMap is ignored.
    authentication_mode = "API"
    # Kept true so existing clusters are not replaced (this field forces a new
    # cluster). The creator shows up as a normal, removable access entry.
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  upgrade_policy {
    support_type = var.support_type
  }

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.cluster,
  ]
}

################################################################################
# Access entries
################################################################################

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.value].principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

################################################################################
# Add-ons
################################################################################

locals {
  # Networking add-ons go in before nodes so nodes come up Ready with the
  # managed (IRSA-enabled) CNI from the start. CoreDNS needs nodes to schedule.
  addons_before_compute = {
    vpc-cni = {
      service_account_role_arn = aws_iam_role.vpc_cni.arn
      # Turns on the VPC CNI network policy agent so the NetworkPolicies that
      # the Argo CD chart creates are actually enforced.
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    kube-proxy = {
      service_account_role_arn = null
      configuration_values     = null
    }
  }

  addons_after_compute = {
    coredns = {
      service_account_role_arn = null
      configuration_values     = null
    }
  }
}

data "aws_eks_addon_version" "this" {
  for_each = merge(local.addons_before_compute, local.addons_after_compute)

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = false
}

resource "aws_eks_addon" "before_compute" {
  for_each = local.addons_before_compute

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = lookup(var.addon_versions, each.key, data.aws_eks_addon_version.this[each.key].version)
  service_account_role_arn    = each.value.service_account_role_arn
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_eks_addon" "after_compute" {
  for_each = local.addons_after_compute

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = lookup(var.addon_versions, each.key, data.aws_eks_addon_version.this[each.key].version)
  service_account_role_arn    = each.value.service_account_role_arn
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

################################################################################
# Managed node group
################################################################################

resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"
  description = "Managed node group template for ${var.cluster_name}"

  update_default_version = true

  # IMDSv2 only, and a hop limit of 1 so pods (which sit one network hop away)
  # cannot read the node's instance-profile credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-node"
    })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = "${var.node_group_name}-"
  node_role_arn          = aws_iam_role.node.arn
  subnet_ids             = aws_subnet.private[*].id
  version                = aws_eks_cluster.this.version
  ami_type               = var.node_ami_type
  capacity_type          = var.node_capacity_type
  instance_types         = var.node_instance_types

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  node_repair_config {
    enabled = true
  }

  tags = merge(var.tags, {
    Name = var.node_group_name
  })

  lifecycle {
    # Replacements (new name, AMI type, instance types) bring the new group up
    # before the old one drains.
    create_before_destroy = true
    # Leave scaling decisions made outside Terraform alone.
    ignore_changes = [scaling_config[0].desired_size]

    precondition {
      condition     = var.node_group_min_size <= var.node_group_desired_size && var.node_group_desired_size <= var.node_group_max_size
      error_message = "Node group sizes must satisfy min <= desired <= max."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_iam_role_policy_attachment.node_cni_legacy,
    aws_eks_addon.before_compute,
  ]
}
