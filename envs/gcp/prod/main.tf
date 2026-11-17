locals {
  labels = {
    environment = "prod"
    project     = "argocd-terraform"
    managed-by  = "terraform"
  }
}

module "cluster" {
  source = "../../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "argocd-prod"
  # Regional cluster: control plane and nodes spread over three zones.
  # Node counts are per zone, so 1-2 per zone means 3-6 nodes in total.
  location            = var.region
  release_channel     = "STABLE"
  deletion_protection = true

  subnet_cidr   = "10.30.0.0/20"
  pods_cidr     = "10.32.0.0/14"
  services_cidr = "10.36.0.0/20"

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  node_machine_type = "e2-standard-4"
  node_spot         = false
  node_min_count    = 1
  node_max_count    = 2

  labels = local.labels
}

module "argocd" {
  source = "../../../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = true
  cloud             = "gcp"
  server_exposure   = "internet"
  allowed_cidrs     = var.admin_cidrs

  bootstrap_app = {
    name                  = "sample-apps"
    application_name      = "nginx-app"
    repo_url              = var.gitops_repo_url
    revision              = var.gitops_revision
    path                  = "argocd/app/overlays/gcp"
    destination_namespace = "nginx"
  }

  # Argo CD must come up after the cluster and nodes, and be removed before them.
  depends_on = [module.cluster]
}
