output "repository_urls" {
  description = "Mapa nome_servico => URL completa do repositorio ECR."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Mapa nome_servico => ARN do repositorio."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}
