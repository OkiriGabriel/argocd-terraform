variable "chart_version" {
  description = "argo-cd Helm chart version from https://argoproj.github.io/argo-helm. Read the chart's upgrade notes before raising it."
  type        = string
  default     = "10.18.0"
}

variable "namespace" {
  description = "Namespace Argo CD is installed into."
  type        = string
  default     = "argocd"
}

variable "domain" {
  description = "Public hostname for Argo CD (used for links, SSO callbacks and notifications). Leave null until you have a DNS name."
  type        = string
  default     = null
}

variable "high_availability" {
  description = "Run Argo CD in HA mode: Redis HA plus 2 replicas of server, repo-server and ApplicationSet controller, with PodDisruptionBudgets. Needs at least 3 nodes."
  type        = bool
  default     = false
}

variable "server_exposure" {
  description = "How the Argo CD API/UI is exposed: \"none\" (ClusterIP, use kubectl port-forward), \"internal-nlb\" (reachable from the VPC only) or \"internet-nlb\" (public NLB limited to allowed_cidrs)."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "internal-nlb", "internet-nlb"], var.server_exposure)
    error_message = "server_exposure must be one of: none, internal-nlb, internet-nlb."
  }
}

variable "allowed_cidrs" {
  description = "Client CIDRs allowed to reach the Argo CD load balancer. Required for internet-nlb. 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "allowed_cidrs must be valid IPv4 CIDRs and must not include 0.0.0.0/0."
  }

  validation {
    condition     = var.server_exposure != "internet-nlb" || length(var.allowed_cidrs) > 0
    error_message = "server_exposure = internet-nlb needs at least one entry in allowed_cidrs."
  }
}

variable "admin_enabled" {
  description = "Keep the built-in local admin account. Turn this off once SSO is configured."
  type        = bool
  default     = true
}

variable "dex_enabled" {
  description = "Deploy Dex for SSO. Off by default to reduce attack surface; enable when you configure dex.config."
  type        = bool
  default     = false
}

variable "extra_values" {
  description = "Additional Helm values documents (YAML strings), merged after the module's values. Use for SSO, RBAC policy, repositories and other site-specific settings."
  type        = list(string)
  default     = []
}
