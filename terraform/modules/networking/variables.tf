variable "project_name" {
  description = "Prefixo para nomear recursos."
  type        = string
}

variable "region" {
  description = "Regiao AWS de deploy."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones a usar (2 minimo)."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (mesma ordem de azs)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (mesma ordem de azs)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "single_nat_gateway" {
  description = "true = 1 NAT compartilhado entre AZs (economia FinOps); false = 1 NAT por AZ (HA)."
  type        = bool
  default     = true
}
