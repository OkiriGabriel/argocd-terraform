module "eks_argocd" {
  source = "../modules/eks-argocd"

  cluster_name            = "argocd-prod"
  kubernetes_version      = "1.32"
  vpc_cidr                = "10.10.0.0/16"
  node_group_name         = "argocd-prod-ng"
  node_instance_types     = ["t3.large"]
  node_group_desired_size = 3
  node_group_min_size     = 2
  node_group_max_size     = 5

  tags = {
    Environment = "prod"
    Project     = "argocd-terraform"
  }
}
