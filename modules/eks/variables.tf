################################################################################
# Cluster
################################################################################

variable "cluster_name" {
  description = "EKS cluster name. Also used as a prefix for related AWS resources."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,38}$", var.cluster_name))
    error_message = "cluster_name must start with a letter, contain only letters, digits and hyphens, and be at most 39 characters (IAM role names are derived from it)."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, for example \"1.35\". EKS upgrades one minor version at a time, so raise this by one step per apply."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.35\"."
  }
}

variable "support_type" {
  description = "EKS upgrade policy. STANDARD auto-upgrades the cluster when standard support ends; EXTENDED keeps the version and bills extended-support fees."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "deletion_protection" {
  description = "Block cluster deletion through the EKS API. Must be set to false and applied before `terraform destroy`."
  type        = bool
  default     = false
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API on a public endpoint. When false, the API is only reachable from inside the VPC (VPN, bastion, CI runner in the VPC)."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Required when endpoint_public_access is true. 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "endpoint_public_access_cidrs must be valid IPv4 CIDRs and must not include 0.0.0.0/0."
  }

  validation {
    condition     = !var.endpoint_public_access || length(var.endpoint_public_access_cidrs) > 0
    error_message = "Set endpoint_public_access_cidrs (for example your office or VPN egress IP as x.x.x.x/32) or set endpoint_public_access = false."
  }
}

variable "cluster_admin_principal_arns" {
  description = "IAM role or user ARNs granted cluster-admin through EKS access entries, in addition to the identity that created the cluster."
  type        = list(string)
  default     = []
}

variable "cluster_log_types" {
  description = "Control plane log types sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Retention for the EKS control plane and VPC flow log groups."
  type        = number
  default     = 90
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the secrets-encryption KMS key is deleted."
  type        = number
  default     = 30
}

################################################################################
# Network
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per AZ. Only NAT gateways and internet-facing load balancers live here."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && length(var.public_subnet_cidrs) <= 3
    error_message = "Provide 2 or 3 public subnet CIDRs (one per AZ)."
  }
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR per AZ for nodes and pods. The VPC CNI gives every pod a VPC IP, so size these generously (a /19 or larger)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2 && length(var.private_subnet_cidrs) <= 3
    error_message = "Provide 2 or 3 private subnet CIDRs (one per AZ)."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (cheaper). Set false for one NAT gateway per AZ so an AZ outage does not cut egress for the others."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

################################################################################
# Nodes
################################################################################

variable "node_group_name" {
  description = "Prefix for the managed node group name. A random suffix is added so the group can be replaced without downtime."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the node group."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_ami_type" {
  description = "EKS managed node group AMI type."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size_gb" {
  description = "Root volume size for worker nodes (gp3, encrypted)."
  type        = number
  default     = 50
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes. Ignored after creation so the cluster autoscaler or manual scaling is not reverted."
  type        = number
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes."
  type        = number

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
}

variable "enable_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore to nodes so they can be reached with Session Manager instead of SSH."
  type        = bool
  default     = true
}

variable "addon_versions" {
  description = "Optional pinned versions for EKS add-ons, keyed by add-on name. Unpinned add-ons use the AWS default version for the cluster's Kubernetes version."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default     = {}
}

variable "legacy_node_cni_policy" {
  description = "Migration aid: keep AmazonEKS_CNI_Policy on the node role while an existing cluster moves the VPC CNI to IRSA. Leave false for new clusters."
  type        = bool
  default     = false
}

variable "legacy_control_plane_public_subnets" {
  description = "Migration aid: keep control plane ENIs in public and private subnets, as the old module did, so an existing cluster's vpc_config is not changed. Leave false for new clusters."
  type        = bool
  default     = false
}
