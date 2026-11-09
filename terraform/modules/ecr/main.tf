# Module: ecr
#
# One ECR private repository per microservice, namespaced petclinic-{env}/{service}.
# Scan-on-push, AES256 encryption, configurable tag immutability, and a lifecycle
# policy that expires untagged images and caps retained image count.
#
# Base tags (Project, Environment, ManagedBy) come from the provider default_tags
# block in the environment root module.

locals {
  name_prefix   = "${var.project}-${var.environment}"
  service_set   = toset(var.service_names)
  repository_ns = local.name_prefix # repos live under petclinic-{env}/

  # Lifecycle: expire untagged images first, then cap total retained count.
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than ${var.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_repository" "this" {
  for_each = local.service_set

  name                 = "${local.repository_ns}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
  }

  tags = merge(var.tags, {
    Name    = "${local.repository_ns}/${each.value}"
    Service = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy     = local.lifecycle_policy
}
