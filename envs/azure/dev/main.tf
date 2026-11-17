locals {
  tags = {
    Environment = "dev"
    Project     = "argocd-terraform"
    ManagedBy   = "terraform"
  }
}

module "cluster" {
  source = "../../../modules/aks"

  cluster_name        = "argocd-dev"
  location            = var.location
  kubernetes_version  = "1.35"
  sku_tier            = "Free"
  deletion_protection = false

  vnet_cidr        = "10.40.0.0/16"
  node_subnet_cidr = "10.40.0.0/22"

  admin_group_object_ids       = var.admin_group_object_ids
  endpoint_public_access_cidrs = var.admin_cidrs

  node_vm_size   = "Standard_D2s_v5"
  node_min_count = 1
  node_max_count = 3

  log_retention_days = 30

  tags = local.tags
}

module "argocd" {
  source = "../../../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = false
  cloud             = "azure"
  server_exposure   = "internet"
  allowed_cidrs     = var.admin_cidrs

  bootstrap_app = {
    name                  = "sample-apps"
    application_name      = "nginx-app"
    repo_url              = var.gitops_repo_url
    revision              = var.gitops_revision
    path                  = "argocd/app/overlays/azure"
    destination_namespace = "nginx"
  }

  # Argo CD must come up after the cluster and nodes, and be removed before them.
  depends_on = [module.cluster]
}
