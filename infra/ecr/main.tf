locals {
  common_tags = merge({ Project = var.project_name }, var.tags)
}

data "aws_caller_identity" "current" {}


resource "aws_ecr_repository" "repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}