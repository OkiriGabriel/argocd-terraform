variable "region" {
  description = "DigitalOcean region for this environment."
  type        = string
  default     = "ams3"
}

variable "admin_cidrs" {
  description = "CIDRs (for example your VPN or office egress IP as x.x.x.x/32) allowed to reach the Kubernetes API and the Argo CD load balancer."
  type        = list(string)
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
