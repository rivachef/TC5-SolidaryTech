variable "project_name" {
  description = "Prefixo (atualmente nao usado nos nomes pra manter URIs limpas)."
  type        = string
}

variable "service_names" {
  description = "Lista de nomes de microsservicos para os quais criar repositorios ECR."
  type        = list(string)
  default     = ["ngo-service", "donation-service", "volunteer-service"]
}

variable "max_image_count" {
  description = "Quantas imagens manter por repositorio (lifecycle policy FinOps)."
  type        = number
  default     = 10
}
