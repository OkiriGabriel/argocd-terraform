terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # This stack creates the state bucket, so it keeps its own (tiny) state
  # locally. Commit nothing from .terraform/; back up terraform.tfstate or
  # migrate it into the bucket afterwards with `terraform init -migrate-state`.
}
