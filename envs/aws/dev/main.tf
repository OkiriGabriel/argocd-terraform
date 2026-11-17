locals {
  tags = {
    Environment = "dev"
    Project     = "argocd-terraform"
    ManagedBy   = "terraform"
  }
}

module "eks" {
  source = "../modules/eks"

  cluster_name       = "argocd-dev"
  kubernetes_version = "1.35"

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.32.0/19", "10.0.64.0/19"]
  single_nat_gateway   = true

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs
  cluster_admin_principal_arns = var.cluster_admin_principal_arns

  node_group_name         = "argocd-dev-ng"
  node_instance_types     = ["t3.medium"]
  node_group_desired_size = 2
  node_group_min_size     = 1
  node_group_max_size     = 3

  log_retention_days                  = 30
  legacy_node_cni_policy              = var.legacy_node_cni_policy
  legacy_control_plane_public_subnets = var.legacy_control_plane_public_subnets

  tags = local.tags
}

module "argocd" {
  source = "../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = false
  server_exposure   = "internet-nlb"
  allowed_cidrs     = var.admin_cidrs

  # Argo CD must come up after nodes and CoreDNS, and be removed before them.
  depends_on = [module.eks]
}
