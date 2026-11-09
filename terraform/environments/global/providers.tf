provider "aws" {
  region = var.aws_region

  # Account-level ("global") resources — not tied to dev or prod. The Environment
  # tag is "global" so these are distinguishable from per-env resources.
  default_tags {
    tags = {
      Project     = var.project
      Environment = "global"
      ManagedBy   = "terraform"
    }
  }
}
