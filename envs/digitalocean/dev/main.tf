module "cluster" {
  source = "../../../modules/doks"

  cluster_name       = "argocd-dev"
  region             = var.region
  kubernetes_version = "1.35"
  ha_control_plane   = false

  vpc_cidr       = "10.60.0.0/20"
  cluster_subnet = "10.244.0.0/16"
  service_subnet = "10.245.0.0/16"

  endpoint_public_access_cidrs = var.admin_cidrs

  node_size      = "s-2vcpu-4gb"
  node_min_count = 2
  node_max_count = 3

  tags = ["argocd-terraform", "dev"]
}

module "argocd" {
  source = "../../../modules/argocd"

  chart_version     = "10.18.0"
  high_availability = false
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
