output "region" {
  value = var.aws_region
}

# Networking
output "vpc_id" {
  value = module.networking.vpc_id
}

# EKS
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl no cluster recem-criado."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ECR
output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

# Databases
output "ngo_db_address" {
  value = module.databases.ngo_db_address
}

output "donation_db_address" {
  value = module.databases.donation_db_address
}

output "dynamodb_table_name" {
  value = module.databases.dynamodb_table_name
}

# Messaging
output "sqs_queue_url" {
  value = module.messaging.queue_url
}

output "sqs_dlq_url" {
  value = module.messaging.dlq_url
}
