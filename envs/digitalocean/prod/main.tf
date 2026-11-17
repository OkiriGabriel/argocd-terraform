module "cluster" {
  source = "../../../modules/doks"

  cluster_name       = "argocd-prod"
  region             = var.region
  kubernetes_version = "1.35"
  ha_control_plane   = true

  vpc_cidr       = "10.70.0.0/20"
  cluster_subnet = "10.246.0.0/16"
  service_subnet = "10.247.0.0/16"

  endpoint_public_access_cidrs = var.admin_cidrs

  node_size      = "s-4vcpu-8gb"
  node_min_count = 3
  node_max_count = 6

  tags = ["argocd-terraform", "prod"]
}

module "argocd" {
  source = "../../../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = true
  cloud             = "digitalocean"
  server_exposure   = "internet"
  allowed_cidrs     = var.admin_cidrs

  bootstrap_app = {
    name                  = "sample-apps"
    application_name      = "nginx-app"
    repo_url              = var.gitops_repo_url
    revision              = var.gitops_revision
    path                  = "argocd/app/overlays/digitalocean"
    destination_namespace = "nginx"
  }

  # Argo CD must come up after the cluster and nodes, and be removed before them.
  depends_on = [module.cluster]
}
