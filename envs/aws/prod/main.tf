locals {
  tags = {
    Environment = "prod"
    Project     = "argocd-terraform"
    ManagedBy   = "terraform"
  }
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name        = "argocd-prod"
  kubernetes_version  = "1.35"
  deletion_protection = true

  vpc_cidr             = "10.10.0.0/16"
  public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.32.0/19", "10.10.64.0/19", "10.10.96.0/19"]
  single_nat_gateway   = false

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs
  cluster_admin_principal_arns = var.cluster_admin_principal_arns

  node_group_name     = "argocd-prod-ng"
  node_instance_types = ["t3.large"]
  # Redis HA places its 3 pods on separate nodes, so keep at least 3.
  node_group_desired_size = 3
  node_group_min_size     = 3
  node_group_max_size     = 6

  log_retention_days                  = 365
  legacy_node_cni_policy              = var.legacy_node_cni_policy
  legacy_control_plane_public_subnets = var.legacy_control_plane_public_subnets

  tags = local.tags
}

module "argocd" {
  source = "../../../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = true
  cloud             = "aws"
  server_exposure   = "internet"
  allowed_cidrs     = var.admin_cidrs

  bootstrap_app = {
    name                  = "sample-apps"
    application_name      = "nginx-app"
    repo_url              = var.gitops_repo_url
    revision              = var.gitops_revision
    path                  = "argocd/app/overlays/aws"
    destination_namespace = "nginx"
  }

  depends_on = [module.eks]
}
