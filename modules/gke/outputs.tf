output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "Control plane endpoint (https URL)."
  value       = "https://${google_container_cluster.this.endpoint}"
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
}

output "cluster_version" {
  description = "Control plane version."
  value       = google_container_cluster.this.master_version
}

output "network_id" {
  description = "VPC network ID."
  value       = google_compute_network.this.id
}

output "workload_identity_pool" {
  description = "Workload Identity pool for binding Kubernetes service accounts to Google service accounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "configure_kubectl" {
  description = "Command to update your local kubeconfig."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --location ${var.location} --project ${var.project_id}"
}
