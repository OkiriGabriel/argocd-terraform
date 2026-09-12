output "cluster_name" {
  value = module.eks_argocd.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_argocd.cluster_endpoint
}

output "configure_kubectl" {
  value = module.eks_argocd.configure_kubectl
}

output "argocd_url" {
  value = module.eks_argocd.argocd_url
}

output "argocd_admin_password_command" {
  value = module.eks_argocd.argocd_admin_password_command
}
