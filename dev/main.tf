module "argocd" {
  source = "../resources"

  cluster_name = "argocd"
  node_group_name = "argocd-ng"
  node_group_desired_size = 2
  node_group_max_size = 2
  node_group_min_size = 1
  vpc_cidr = "10.0.0.0/16"
  

tags = {
    Environment = "dev"
    Project     = "argocd-project"
  }
}