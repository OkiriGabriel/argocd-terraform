terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
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

  # Partial configuration: bucket, key and region come from backend.hcl.
  #   cp backend.hcl.example backend.hcl   # then edit
  #   terraform init -backend-config=backend.hcl
  # State locking uses an S3 lockfile (use_lockfile), so no DynamoDB table is needed.
  backend "s3" {}
}
