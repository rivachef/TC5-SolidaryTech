variable "project_name" {
  description = "Prefixo para nomear filas."
  type        = string
}

variable "queue_name" {
  description = "Nome da fila principal."
  type        = string
  default     = "solidary-donations"
}

variable "visibility_timeout_seconds" {
  description = "Tempo durante o qual a mensagem fica invisivel apos receive."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Quanto tempo as mensagens ficam na fila (segundos). Default 14 dias."
  type        = number
  default     = 1209600 # 14 dias
}

variable "max_receive_count" {
  description = "Quantas vezes uma mensagem pode falhar antes de ir para DLQ."
  type        = number
  default     = 5
}
