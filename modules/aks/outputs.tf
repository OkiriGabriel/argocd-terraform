output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  description = "Resource group holding the cluster."
  value       = azurerm_resource_group.this.name
}

output "cluster_endpoint" {
  description = "API server URL."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_version" {
  description = "Current Kubernetes version."
  value       = azurerm_kubernetes_cluster.this.current_kubernetes_version
}

output "oidc_issuer_url" {
  description = "OIDC issuer for Workload Identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "deployer_role_assignment_id" {
  description = "Role assignment that lets Terraform talk to the cluster; Kubernetes resources should depend on it."
  value       = azurerm_role_assignment.deployer_cluster_admin.id
}

output "configure_kubectl" {
  description = "Commands to update your local kubeconfig (Entra ID login through kubelogin)."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} && kubelogin convert-kubeconfig -l azurecli"
}
