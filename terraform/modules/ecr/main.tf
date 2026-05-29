resource "aws_ecr_repository" "this" {
  for_each = toset(var.service_names)

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true # facilita destroy do hackathon; em producao real, false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = each.value
    Component = "container-registry"
  }
}

resource "aws_ecr_lifecycle_policy" "keep_last" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ${var.max_image_count} imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
