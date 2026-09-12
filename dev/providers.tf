variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "eu-west-1"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "argocd-terraform"
      ManagedBy   = "terraform"
    }
  }
}
