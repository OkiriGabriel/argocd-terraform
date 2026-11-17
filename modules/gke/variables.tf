variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the network, NAT and KMS key."
  type        = string
}

variable "location" {
  description = "Cluster location. A region (for example europe-west1) gives a regional, highly available control plane; a zone (europe-west1-b) is cheaper."
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name. Also used as a prefix for related resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and hyphens, 3-40 characters."
  }
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR or STABLE. GKE upgrades the control plane and nodes within the channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "kubernetes_version" {
  description = "Minimum control plane version (for example \"1.35\"). Null lets the release channel pick."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Block cluster deletion. Set to false and apply before `terraform destroy`."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Expose the control plane on a public IP. When false only the private endpoint is used."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the control plane (master authorized networks). 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "endpoint_public_access_cidrs must be valid IPv4 CIDRs and must not include 0.0.0.0/0."
  }

  validation {
    condition     = !var.endpoint_public_access || length(var.endpoint_public_access_cidrs) > 0
    error_message = "Set endpoint_public_access_cidrs or set endpoint_public_access = false."
  }
}

variable "subnet_cidr" {
  description = "Primary range of the node subnet."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary range for pod IPs (VPC-native)."
  type        = string
}

variable "services_cidr" {
  description = "Secondary range for Service IPs."
  type        = string
}

variable "node_machine_type" {
  description = "Machine type for the node pool."
  type        = string
}

variable "node_disk_size_gb" {
  description = "Boot disk size for nodes."
  type        = number
  default     = 50
}

variable "node_spot" {
  description = "Use Spot VMs (cheaper, can be reclaimed). Fine for dev."
  type        = bool
  default     = false
}

variable "node_min_count" {
  description = "Minimum nodes per zone."
  type        = number
}

variable "node_max_count" {
  description = "Maximum nodes per zone."
  type        = number
}

variable "labels" {
  description = "Labels applied to supported resources."
  type        = map(string)
  default     = {}
}
