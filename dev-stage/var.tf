# variables.tf
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  default     = "main-eks-cluster"
}

variable "node_group_name" {
  description = "Name of the EKS node group"
  default     = "main-eks-node-group"
}

variable "node_group_desired_size" {
  description = "Desired size of the EKS node group"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum size of the EKS node group"
  type        = number
  default     = 3
}

variable "node_group_min_size" {
  description = "Minimum size of the EKS node group"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "eks-demo"
  }
}
