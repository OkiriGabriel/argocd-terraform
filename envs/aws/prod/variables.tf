variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "eu-west-1"
}

variable "admin_cidrs" {
  description = "CIDRs (for example your VPN or office egress IP as x.x.x.x/32) allowed to reach the Kubernetes API and the Argo CD load balancer."
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "Extra IAM role/user ARNs that get cluster-admin through EKS access entries (for example an SSO admin role or a CI role)."
  type        = list(string)
  default     = []
}

variable "legacy_node_cni_policy" {
  description = "Migration aid for clusters built from the old eks-argocd module. See MIGRATION.md."
  type        = bool
  default     = false
}

variable "legacy_control_plane_public_subnets" {
  description = "Migration aid for clusters built from the old eks-argocd module. See MIGRATION.md."
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD syncs the sample app from."
  type        = string
  default     = "https://github.com/OkiriGabriel/argocd-terraform.git"
}

variable "gitops_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}
