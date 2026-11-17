output "namespace" {
  description = "Namespace Argo CD runs in."
  value       = helm_release.argocd.namespace
}

output "chart_version" {
  description = "Deployed argo-cd chart version."
  value       = helm_release.argocd.version
}

output "url" {
  description = "Argo CD URL. Null when server_exposure is none or the load balancer is still provisioning."
  value = local.expose_lb ? try(
    "https://${data.kubernetes_service_v1.argocd_server[0].status[0].load_balancer[0].ingress[0].hostname}",
    null,
  ) : null
}

output "port_forward_command" {
  description = "Reach the UI without a load balancer."
  value       = "kubectl -n ${helm_release.argocd.namespace} port-forward svc/argocd-server 8080:443"
}

output "admin_password_command" {
  description = "Prints the initial admin password. Change it after first login, then delete the secret."
  value       = "kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}
