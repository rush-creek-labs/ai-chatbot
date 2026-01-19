################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL from anywhere (App Runner + migrations)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

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

resource "aws_security_group" "apprunner" {
  name        = "${var.environment}-apprunner-sg"
  description = "Security group for App Runner VPC connector"
  vpc_id      = data.aws_vpc.default.id

  # Allow all outbound traffic (needed for RDS, Bedrock, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = local.tags
}

################################################################################
# VPC Endpoints for AWS Services
# Required because App Runner with VPC egress cannot reach AWS services
# via public internet without a NAT Gateway
################################################################################

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

################################################################################
# App Runner VPC Connector
################################################################################

resource "aws_apprunner_vpc_connector" "chatbot" {
  vpc_connector_name = "${local.name}-connector"
  subnets            = local.apprunner_subnet_ids
  security_groups    = [aws_security_group.apprunner.id]

  tags = local.tags
}
