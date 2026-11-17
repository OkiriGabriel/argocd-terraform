output "cluster_name" {
  value = module.cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "cluster_version" {
  value = module.cluster.cluster_version
}

output "configure_kubectl" {
  value = module.cluster.configure_kubectl
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
