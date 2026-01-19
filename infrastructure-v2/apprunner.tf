################################################################################
# Security Group for App Runner VPC Connector
################################################################################

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
# VPC Connector (required for App Runner to access RDS)
################################################################################

resource "aws_apprunner_vpc_connector" "chatbot" {
  vpc_connector_name = "${local.name}-connector"
  subnets            = local.apprunner_subnet_ids # Filtered to App Runner supported AZs
  security_groups    = [aws_security_group.apprunner.id]

  tags = local.tags
}

################################################################################
# Auto Scaling Configuration
################################################################################

resource "aws_apprunner_auto_scaling_configuration_version" "chatbot" {
  auto_scaling_configuration_name = "${local.name}-autoscaling"

  max_concurrency = 100 # requests per instance before scaling
  max_size        = 3   # max instances
  min_size        = 1   # min instances (cost savings)

  tags = local.tags
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "apprunner" {
  name              = "/apprunner/${local.name}"
  retention_in_days = 14

  tags = local.tags
}

################################################################################
# App Runner Service
################################################################################

resource "aws_apprunner_service" "chatbot" {
  service_name = "${local.name}-apprunner"

  source_configuration {
    auto_deployments_enabled = false # Manual deployments via AWS CLI/Console

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }

    image_repository {
      image_identifier      = "${data.aws_ecr_repository.chatbot.repository_url}:latest"
      image_repository_type = "ECR"

      image_configuration {
        port = "3000"

        runtime_environment_variables = {
          NODE_ENV        = "production"
          AWS_REGION      = var.aws_region
          AUTH_TRUST_HOST = "true"
          # Note: AUTH_URL must be updated after initial deployment
          # once the service URL is known. Use:
          # aws apprunner update-service --service-arn <arn> \
          #   --source-configuration '{"ImageRepository":{"ImageConfiguration":{"RuntimeEnvironmentVariables":{"AUTH_URL":"https://<service-url>"}}}}'
        }

        runtime_environment_secrets = {
          POSTGRES_URL = data.aws_secretsmanager_secret.postgres_url.arn
          AUTH_SECRET  = data.aws_secretsmanager_secret.auth_secret.arn
        }
      }
    }
  }

  instance_configuration {
    cpu               = "1024" # 1 vCPU
    memory            = "2048" # 2 GB
    instance_role_arn = aws_iam_role.apprunner_instance.arn
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.chatbot.arn
    }
  }

  # Health check configuration - maximized for Next.js startup (20-30s)
  # Note: App Runner limits timeout to 20s max. With interval=20 and unhealthy_threshold=20,
  # the service has ~400 seconds (6.6 min) to start before being marked unhealthy.
  health_check_configuration {
    protocol            = "HTTP"
    path                = "/api/health"
    interval            = 20 # seconds between checks (max allowed)
    timeout             = 20 # wait 20s for response (max allowed)
    healthy_threshold   = 1  # 1 success = healthy
    unhealthy_threshold = 20 # 20 failures before unhealthy (max allowed)
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.chatbot.arn

  # Ensure VPC endpoints are ready before the service starts
  depends_on = [
    aws_vpc_endpoint.bedrock_runtime,
    aws_vpc_endpoint.secretsmanager
  ]

  tags = local.tags
}
