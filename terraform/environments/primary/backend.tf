terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "tc5-solidarytech-terraform-state"
    key            = "environments/primary/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tc5-solidarytech-terraform-lock"
    encrypt        = true
  }
}
