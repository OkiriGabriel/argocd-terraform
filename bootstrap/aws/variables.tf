variable "aws_region" {
  description = "Region for the state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "How long old state versions are kept for recovery."
  type        = number
  default     = 90
}
