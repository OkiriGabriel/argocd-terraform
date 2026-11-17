variable "cluster_name" {
  description = "AKS cluster name. Also used as a prefix for related resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and hyphens, 3-40 characters."
  }
}

variable "location" {
  description = "Azure region, for example westeurope."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes minor version, for example \"1.35\". Patch versions are applied automatically (automatic_upgrade_channel = patch)."
  type        = string
}

variable "sku_tier" {
  description = "Free (no SLA) or Standard (uptime SLA, recommended for production)."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "deletion_protection" {
  description = "Put a CanNotDelete lock on the resource group. Remove it (set false and apply) before `terraform destroy`."
  type        = bool
  default     = false
}

variable "admin_group_object_ids" {
  description = "Microsoft Entra ID group object IDs that get cluster-admin. Local (certificate) accounts are disabled, so at least one is required."
  type        = list(string)

  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "Provide at least one Entra ID admin group object ID."
  }
}

variable "private_cluster" {
  description = "Make the API server private (reachable only from the VNet or peered networks)."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API server (authorized IP ranges). Required unless private_cluster is true. 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "endpoint_public_access_cidrs must be valid IPv4 CIDRs and must not include 0.0.0.0/0."
  }

  validation {
    condition     = var.private_cluster || length(var.endpoint_public_access_cidrs) > 0
    error_message = "Set endpoint_public_access_cidrs or set private_cluster = true."
  }
}

variable "vnet_cidr" {
  description = "Address space of the VNet."
  type        = string
}

variable "node_subnet_cidr" {
  description = "Subnet for nodes. Pods use an overlay range, so this can be small."
  type        = string
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod IPs. Must not overlap the VNet or anything it peers with."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "CIDR for Service IPs."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS IP; must be inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "node_vm_size" {
  description = "VM size for the node pool."
  type        = string
}

variable "node_os_disk_size_gb" {
  description = "OS disk size for nodes."
  type        = number
  default     = 64
}

variable "node_min_count" {
  description = "Minimum nodes."
  type        = number
}

variable "node_max_count" {
  description = "Maximum nodes."
  type        = number
}

variable "zones" {
  description = "Availability zones for nodes. Use [] in regions without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "host_encryption" {
  description = "Encrypt temp disks and caches on the host. Needs the EncryptionAtHost feature registered on the subscription."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention for the Log Analytics workspace (control plane and container logs)."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default     = {}
}
