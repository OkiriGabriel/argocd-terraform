terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
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

  # Partial configuration: storage account details come from backend.hcl.
  #   cp backend.hcl.example backend.hcl   # then edit
  #   terraform init -backend-config=backend.hcl
  # Azure Blob leases lock state natively; access uses Entra ID, not keys.
  backend "azurerm" {}
}
