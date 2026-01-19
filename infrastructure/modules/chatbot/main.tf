################################################################################
# Locals
################################################################################

locals {
  name = "${var.environment}-ai-chatbot"
  tags = {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

################################################################################
# Data Sources
################################################################################

# Get current AWS account
data "aws_caller_identity" "current" {}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC (use default)
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

# Get subnet details for filtering
data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

# Filter subnets to only those in App Runner supported AZs
locals {
  apprunner_subnet_ids = [
    for subnet in data.aws_subnet.default : subnet.id
    if contains(local.apprunner_supported_azs, subnet.availability_zone_id)
  ]
}
