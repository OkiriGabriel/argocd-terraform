terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.11"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
  }

  # Partial configuration: bucket and prefix come from backend.hcl.
  #   cp backend.hcl.example backend.hcl   # then edit
  #   terraform init -backend-config=backend.hcl
  # GCS locks state natively.
  backend "gcs" {}
}
