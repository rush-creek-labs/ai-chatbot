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
  default     = "dev"
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
