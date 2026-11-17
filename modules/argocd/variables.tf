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

variable "cloud" {
  description = "Cloud the cluster runs on. Selects load balancer annotations: aws, gcp, azure or digitalocean."
  type        = string

  validation {
    condition     = contains(["aws", "gcp", "azure", "digitalocean"], var.cloud)
    error_message = "cloud must be one of: aws, gcp, azure, digitalocean."
  }
}

variable "server_exposure" {
  description = "How the Argo CD API/UI is exposed: \"none\" (ClusterIP, use kubectl port-forward), \"internal\" (private load balancer, reachable from the VPC/VNet only) or \"internet\" (public load balancer limited to allowed_cidrs)."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "internal", "internet"], var.server_exposure)
    error_message = "server_exposure must be one of: none, internal, internet."
  }

  validation {
    condition     = !(var.cloud == "digitalocean" && var.server_exposure == "internal")
    error_message = "DigitalOcean load balancers are always public; use none or internet."
  }
}

variable "allowed_cidrs" {
  description = "Client CIDRs allowed to reach the Argo CD load balancer (enforced through loadBalancerSourceRanges on every supported cloud). Required for internet. 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "allowed_cidrs must be valid IPv4 CIDRs and must not include 0.0.0.0/0."
  }

  validation {
    condition     = var.server_exposure != "internet" || length(var.allowed_cidrs) > 0
    error_message = "server_exposure = internet needs at least one entry in allowed_cidrs."
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

variable "apps_chart_version" {
  description = "argocd-apps Helm chart version, used to create the bootstrap AppProject and Application."
  type        = string
  default     = "2.0.8"
}

variable "bootstrap_app" {
  description = <<-EOT
    GitOps bootstrap. When set, Terraform creates an AppProject that may only
    deploy repo_url into destination_namespace, and an auto-syncing Application
    for path. Set to null to manage Applications yourself.
  EOT
  type = object({
    # AppProject name.
    name = string
    # Application name; defaults to the project name.
    application_name      = optional(string)
    repo_url              = string
    revision              = optional(string, "main")
    path                  = string
    destination_namespace = string
    # Namespaced kinds the project may create, as "group/Kind" ("" group = core).
    allowed_kinds = optional(list(string), [
      "/ConfigMap",
      "/Service",
      "apps/Deployment",
      "policy/PodDisruptionBudget",
      "networking.k8s.io/NetworkPolicy",
    ])
  })
  default = null
}
