terraform {
  required_version = ">= 1.14.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

################################################################################
# Variables
################################################################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod, staging)"
  type        = string
  default     = "sandbox"
}

variable "db_password" {
  description = "Password for the RDS PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "auth_secret" {
  description = "Secret key for NextAuth.js JWT signing"
  type        = string
  sensitive   = true
}

variable "apprunner_services" {
  description = "List of App Runner service names to create (empty = no services, allows staged deployment)"
  type        = list(string)
  default     = []
}

################################################################################
# Module
################################################################################

module "chatbot" {
  source = "../modules/chatbot"

  aws_region         = var.aws_region
  environment        = var.environment
  db_password        = var.db_password
  auth_secret        = var.auth_secret
  apprunner_services = var.apprunner_services
}
