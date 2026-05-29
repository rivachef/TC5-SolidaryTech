variable "project_name" {
  description = "Prefixo para nomear recursos."
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes."
  type        = string
  default     = "1.31"
}

variable "cluster_role_arn" {
  description = "ARN do role do cluster EKS. AWS Academy: usar LabRole."
  type        = string
}

variable "node_role_arn" {
  description = "ARN do role do node group. AWS Academy: usar LabRole."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets onde o cluster e os nodes operarao (privadas)."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets publicas para LoadBalancers."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group dos nodes (criado em networking)."
  type        = string
}

variable "node_instance_types" {
  description = "Tipos de instancia do node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade minima de nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade maxima de nodes (autoscaling)."
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Tamanho do disco de cada node em GB."
  type        = number
  default     = 20
}

variable "endpoint_public_access" {
  description = "Habilitar acesso publico ao endpoint do cluster (true necessario fora da VPC)."
  type        = bool
  default     = true
}
