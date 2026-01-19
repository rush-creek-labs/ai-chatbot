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
  profile = "default"
}

locals {
  name = "${var.environment}-ai-chatbot"
  tags = {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "apprunner"
  }
}

################################################################################
# Data Sources - Reference existing infrastructure
################################################################################

# Get current AWS account
data "aws_caller_identity" "current" {}

# Reference existing ECR repository (created by infrastructure/)
data "aws_ecr_repository" "chatbot" {
  name = "ai-chatbot"
}

# Reference existing secrets (created by infrastructure/)
data "aws_secretsmanager_secret" "postgres_url" {
  name = "${var.environment}/chatbot/postgres-url"
}

data "aws_secretsmanager_secret" "auth_secret" {
  name = "${var.environment}/chatbot/auth-secret"
}

# VPC and subnets (same default VPC as ECS)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# App Runner supported availability zones in us-east-1
# Note: use1-az3 is NOT supported by App Runner
locals {
  apprunner_supported_azs = ["use1-az1", "use1-az2", "use1-az4", "use1-az5", "use1-az6"]
}

# Filter subnets to only those in App Runner supported AZs
data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  apprunner_subnet_ids = [
    for subnet in data.aws_subnet.default : subnet.id
    if contains(local.apprunner_supported_azs, subnet.availability_zone_id)
  ]
}

################################################################################
# VPC Endpoints for AWS Services (required for VPC egress)
# When App Runner uses VPC egress, it can't reach AWS services via public
# internet without a NAT Gateway. VPC endpoints provide private connectivity.
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
    description = "HTTPS from VPC"
  }

  tags = local.tags
}

# Bedrock Runtime VPC Endpoint (for model invocations)
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.apprunner_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-bedrock-runtime-endpoint"
  })
}

# Secrets Manager VPC Endpoint (for runtime secrets)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.apprunner_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-secretsmanager-endpoint"
  })
}
