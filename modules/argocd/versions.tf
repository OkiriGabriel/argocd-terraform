terraform {
  required_version = ">= 1.10.0"

  # Providers are configured by the caller. Keeping provider blocks out of the
  # module lets callers use count/for_each/depends_on on it and lets the module
  # be removed without orphaning resources.
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}
