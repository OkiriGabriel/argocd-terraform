module "eks_argocd" {
  source = "../modules/eks-argocd"

  cluster_name            = "argocd-dev"
  kubernetes_version      = "1.32"
  vpc_cidr                = "10.0.0.0/16"
  node_group_name         = "argocd-dev-ng"
  node_instance_types     = ["t3.medium"]
  node_group_desired_size = 2
  node_group_min_size     = 1
  node_group_max_size     = 3

  tags = {
    Environment = "dev"
    Project     = "argocd-terraform"
  }
}
