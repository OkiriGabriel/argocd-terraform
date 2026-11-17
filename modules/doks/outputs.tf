output "cluster_id" {
  description = "DOKS cluster ID."
  value       = digitalocean_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "DOKS cluster name."
  value       = digitalocean_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server URL."
  value       = digitalocean_kubernetes_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = digitalocean_kubernetes_cluster.this.version
}

output "vpc_id" {
  description = "VPC ID."
  value       = digitalocean_vpc.this.id
}

output "configure_kubectl" {
  description = "Command to update your local kubeconfig."
  value       = "doctl kubernetes cluster kubeconfig save ${digitalocean_kubernetes_cluster.this.id}"
}
