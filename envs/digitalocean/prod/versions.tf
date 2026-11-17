terraform {
  required_version = ">= 1.10.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.107"
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

  # State lives in a DigitalOcean Spaces bucket through the S3 backend.
  #   cp backend.hcl.example backend.hcl   # then edit
  #   export AWS_ACCESS_KEY_ID=<spaces key> AWS_SECRET_ACCESS_KEY=<spaces secret>
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
