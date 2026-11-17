# State migration from the single "eks_argocd" module (commit 83281ae and
# earlier) to the separate "eks" and "argocd" modules. These blocks are no-ops
# on a fresh state. Keep them until every copy of this stack has been applied
# once with this version, then delete them. See MIGRATION.md.

# --- Network -----------------------------------------------------------------
moved {
  from = module.eks_argocd.aws_vpc.this
  to   = module.eks.aws_vpc.this
}

moved {
  from = module.eks_argocd.aws_subnet.public
  to   = module.eks.aws_subnet.public
}

moved {
  from = module.eks_argocd.aws_subnet.private
  to   = module.eks.aws_subnet.private
}

moved {
  from = module.eks_argocd.aws_internet_gateway.this
  to   = module.eks.aws_internet_gateway.this
}

moved {
  from = module.eks_argocd.aws_eip.nat
  to   = module.eks.aws_eip.nat[0]
}

moved {
  from = module.eks_argocd.aws_nat_gateway.this
  to   = module.eks.aws_nat_gateway.this[0]
}

moved {
  from = module.eks_argocd.aws_route_table.public
  to   = module.eks.aws_route_table.public
}

moved {
  from = module.eks_argocd.aws_route_table.private
  to   = module.eks.aws_route_table.private[0]
}

moved {
  from = module.eks_argocd.aws_route_table_association.public
  to   = module.eks.aws_route_table_association.public
}

moved {
  from = module.eks_argocd.aws_route_table_association.private
  to   = module.eks.aws_route_table_association.private
}

# --- IAM ---------------------------------------------------------------------
moved {
  from = module.eks_argocd.aws_iam_role.cluster
  to   = module.eks.aws_iam_role.cluster
}

moved {
  from = module.eks_argocd.aws_iam_role_policy_attachment.cluster
  to   = module.eks.aws_iam_role_policy_attachment.cluster
}

moved {
  from = module.eks_argocd.aws_iam_role.node
  to   = module.eks.aws_iam_role.node
}

moved {
  from = module.eks_argocd.aws_iam_role_policy_attachment.node["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"]
  to   = module.eks.aws_iam_role_policy_attachment.node["worker"]
}

# The node-role CNI policy is parked on the legacy resource. With
# legacy_node_cni_policy = true it stays attached for the switch-over apply;
# with false it is detached. AmazonEC2ContainerRegistryReadOnly is not moved:
# it is replaced by the narrower AmazonEC2ContainerRegistryPullOnly.
moved {
  from = module.eks_argocd.aws_iam_role_policy_attachment.node["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]
  to   = module.eks.aws_iam_role_policy_attachment.node_cni_legacy[0]
}

# --- EKS -----------------------------------------------------------------------
moved {
  from = module.eks_argocd.aws_eks_cluster.this
  to   = module.eks.aws_eks_cluster.this
}

moved {
  from = module.eks_argocd.aws_eks_node_group.this
  to   = module.eks.aws_eks_node_group.this
}

moved {
  from = module.eks_argocd.aws_eks_addon.this["vpc-cni"]
  to   = module.eks.aws_eks_addon.before_compute["vpc-cni"]
}

moved {
  from = module.eks_argocd.aws_eks_addon.this["kube-proxy"]
  to   = module.eks.aws_eks_addon.before_compute["kube-proxy"]
}

moved {
  from = module.eks_argocd.aws_eks_addon.this["coredns"]
  to   = module.eks.aws_eks_addon.after_compute["coredns"]
}

# --- Argo CD -----------------------------------------------------------------
moved {
  from = module.eks_argocd.helm_release.argocd
  to   = module.argocd.helm_release.argocd
}
