# Provider version constraints for the github-oidc module.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Used to fetch the GitHub OIDC issuer certificate so the provider
    # thumbprint is computed dynamically rather than hardcoded.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
