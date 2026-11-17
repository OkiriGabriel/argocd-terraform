terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.11"
    }
  }
  # Local state on purpose: this stack creates the bucket. Back it up.
}

variable "project_id" {
  description = "GCP project that holds the state bucket."
  type        = string
}

variable "location" {
  description = "Bucket location (region or multi-region such as EU)."
  type        = string
  default     = "EU"
}

variable "bucket_name" {
  description = "Globally unique bucket name for Terraform state."
  type        = string
}

provider "google" {
  project = var.project_id
}

resource "google_storage_bucket" "state" {
  name     = var.bucket_name
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  # Keep the last 20 versions of each state file, drop older ones after 90 days.
  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    project    = "argocd-terraform"
    component  = "terraform-state"
    managed-by = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "bucket_name" {
  description = "Use as `bucket` in envs/gcp/*/backend.hcl."
  value       = google_storage_bucket.state.name
}
