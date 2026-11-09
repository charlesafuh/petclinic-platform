provider "aws" {
  region = var.aws_region

  # Common tags applied to every AWS resource that supports tagging.
  # Modules may merge additional service-specific tags on top of these.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
