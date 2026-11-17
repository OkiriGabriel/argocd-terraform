variable "cluster_name" {
  description = "DOKS cluster name. Also used as a prefix for the VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and hyphens, 3-40 characters."
  }
}

variable "region" {
  description = "DigitalOcean region slug, for example ams3 or fra1."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, for example \"1.35\". The newest DOKS patch release for it is used, and patch upgrades are applied automatically in the maintenance window."
  type        = string
}

variable "ha_control_plane" {
  description = "Run a highly available control plane (recommended for production; extra cost)."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the API server (control plane firewall). 0.0.0.0/0 is rejected."
  type        = list(string)

  validation {
    condition     = length(var.endpoint_public_access_cidrs) > 0 && alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "endpoint_public_access_cidrs needs at least one valid IPv4 CIDR and must not include 0.0.0.0/0."
  }
}

variable "vpc_cidr" {
  description = "IP range of the VPC the nodes live in."
  type        = string
}

variable "cluster_subnet" {
  description = "Pod CIDR. Must not overlap the VPC or other VPCs in the account."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_subnet" {
  description = "Service CIDR. Must not overlap the VPC or cluster_subnet."
  type        = string
  default     = "10.245.0.0/16"
}

variable "node_size" {
  description = "Droplet size slug for nodes, for example s-2vcpu-4gb."
  type        = string
}

variable "node_min_count" {
  description = "Minimum nodes (autoscaler)."
  type        = number
}

variable "node_max_count" {
  description = "Maximum nodes (autoscaler)."
  type        = number
}

variable "maintenance_day" {
  description = "Day for automatic patch upgrades (monday ... sunday, or any)."
  type        = string
  default     = "sunday"
}

variable "maintenance_start_time" {
  description = "UTC start time for the maintenance window, HH:MM."
  type        = string
  default     = "03:00"
}

variable "tags" {
  description = "Tags for the cluster and node pool (lowercase strings)."
  type        = list(string)
  default     = []
}
