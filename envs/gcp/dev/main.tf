locals {
  labels = {
    environment = "dev"
    project     = "argocd-terraform"
    managed-by  = "terraform"
  }
}

module "cluster" {
  source = "../../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "argocd-dev"
  # Zonal cluster with Spot nodes keeps dev cheap.
  location            = "europe-west1-b"
  release_channel     = "REGULAR"
  deletion_protection = false

  subnet_cidr   = "10.20.0.0/20"
  pods_cidr     = "10.24.0.0/14"
  services_cidr = "10.28.0.0/20"

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  node_machine_type = "e2-standard-2"
  node_spot         = true
  node_min_count    = 1
  node_max_count    = 3

  labels = local.labels
}

module "argocd" {
  source = "../../../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = false
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
