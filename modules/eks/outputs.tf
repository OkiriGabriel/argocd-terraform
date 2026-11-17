output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = aws_eks_cluster.this.version
}

output "configure_kubectl" {
  description = "Command to update your local kubeconfig."
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.this.name}"
}

output "argocd_url" {
  description = "Argo CD UI URL (NLB hostname)."
  value       = try("https://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname}", null)
}

output "argocd_admin_password_command" {
  description = "Command to print the initial Argo CD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}

data "aws_region" "current" {}
