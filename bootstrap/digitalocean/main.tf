terraform {
  required_version = ">= 1.10.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.107"
    }
  }
  # Local state on purpose: this stack creates the bucket. Back it up.
}

# Needs DIGITALOCEAN_TOKEN plus SPACES_ACCESS_KEY_ID / SPACES_SECRET_ACCESS_KEY
# in the environment (Spaces keys are separate from the API token).
provider "digitalocean" {}

variable "region" {
  description = "Spaces region."
  type        = string
  default     = "ams3"
}

variable "bucket_name" {
  description = "Globally unique Spaces bucket name for Terraform state."
  type        = string
}

resource "digitalocean_spaces_bucket" "state" {
  name   = var.bucket_name
  region = var.region
  acl    = "private"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "expire-old-state-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }

    abort_incomplete_multipart_upload_days = 7
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "bucket_name" {
  description = "Use as `bucket` in envs/digitalocean/*/backend.hcl."
  value       = digitalocean_spaces_bucket.state.name
}

output "endpoint" {
  description = "Use as endpoints.s3 in envs/digitalocean/*/backend.hcl."
  value       = "https://${var.region}.digitaloceanspaces.com"
}
