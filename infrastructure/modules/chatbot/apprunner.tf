################################################################################
# Auto Scaling Configuration (per service)
################################################################################

resource "aws_apprunner_auto_scaling_configuration_version" "chatbot" {
  for_each = toset(var.apprunner_services)

  auto_scaling_configuration_name = "${local.name}-${each.key}-autoscaling"

  max_concurrency = 100 # requests per instance before scaling
  max_size        = 3   # max instances
  min_size        = 1   # min instances (cost savings)

  tags = local.tags
}

################################################################################
# CloudWatch Log Groups (per service)
################################################################################

resource "aws_cloudwatch_log_group" "apprunner" {
  for_each = toset(var.apprunner_services)

  name              = "/apprunner/${local.name}-${each.key}"
  retention_in_days = 14

  tags = local.tags
}

################################################################################
# App Runner Services (conditionally created based on apprunner_services list)
################################################################################

resource "aws_apprunner_service" "chatbot" {
  for_each = toset(var.apprunner_services)

  service_name = "${local.name}-${each.key}"

  source_configuration {
    auto_deployments_enabled = false # Manual deployments via AWS CLI/Console

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }

    image_repository {
      image_identifier      = "${aws_ecr_repository.chatbot.repository_url}:latest"
      image_repository_type = "ECR"

      image_configuration {
        port = "3000"

        runtime_environment_variables = {
          NODE_ENV        = "production"
          AWS_REGION      = var.aws_region
          AUTH_TRUST_HOST = "true" # Allows NextAuth to use Host header, no explicit AUTH_URL needed
        }

        runtime_environment_secrets = {
          POSTGRES_URL = aws_secretsmanager_secret.postgres_url.arn
          AUTH_SECRET  = aws_secretsmanager_secret.auth_secret.arn
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

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.chatbot[each.key].arn

  # Ensure VPC endpoints are ready before the service starts
  depends_on = [
    aws_vpc_endpoint.bedrock_runtime,
    aws_vpc_endpoint.secretsmanager
  ]

  tags = local.tags
}
