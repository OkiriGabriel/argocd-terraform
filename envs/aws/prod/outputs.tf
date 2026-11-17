output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "configure_kubectl" {
  value = module.eks.configure_kubectl
}

output "argocd_url" {
  value = module.argocd.url
}

output "argocd_port_forward_command" {
  value = module.argocd.port_forward_command
}

output "argocd_admin_password_command" {
  value = module.argocd.admin_password_command
}
