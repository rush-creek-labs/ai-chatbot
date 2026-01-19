################################################################################
# Base Infrastructure Outputs (always available)
################################################################################

output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = aws_ecr_repository.chatbot.repository_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgres.db_name
}

output "vpc_connector_arn" {
  description = "ARN of the VPC connector"
  value       = aws_apprunner_vpc_connector.chatbot.arn
}

################################################################################
# App Runner Service Outputs (dynamic based on apprunner_services)
################################################################################

output "apprunner_service_urls" {
  description = "HTTPS URLs of created App Runner services"
  value = {
    for name, service in aws_apprunner_service.chatbot :
    name => "https://${service.service_url}"
  }
}

output "apprunner_service_arns" {
  description = "ARNs of created App Runner services"
  value = {
    for name, service in aws_apprunner_service.chatbot :
    name => service.arn
  }
}

output "apprunner_service_ids" {
  description = "Service IDs for deployments"
  value = {
    for name, service in aws_apprunner_service.chatbot :
    name => service.service_id
  }
}

################################################################################
# Deployment Commands
################################################################################

output "deployment_commands" {
  description = "Commands to trigger new deployments for each service"
  value = {
    for name, service in aws_apprunner_service.chatbot :
    name => "aws apprunner start-deployment --service-arn ${service.arn}"
  }
}

output "update_auth_url_commands" {
  description = "Commands to update AUTH_URL after initial deployment"
  value = {
    for name, service in aws_apprunner_service.chatbot :
    name => <<-EOT
      aws apprunner update-service \
        --service-arn ${service.arn} \
        --source-configuration '{
          "ImageRepository": {
            "ImageIdentifier": "${aws_ecr_repository.chatbot.repository_url}:latest",
            "ImageRepositoryType": "ECR",
            "ImageConfiguration": {
              "Port": "3000",
              "RuntimeEnvironmentVariables": {
                "NODE_ENV": "production",
                "AWS_REGION": "${var.aws_region}",
                "AUTH_TRUST_HOST": "true",
                "AUTH_URL": "https://${service.service_url}"
              },
              "RuntimeEnvironmentSecrets": {
                "POSTGRES_URL": "${aws_secretsmanager_secret.postgres_url.arn}",
                "AUTH_SECRET": "${aws_secretsmanager_secret.auth_secret.arn}"
              }
            }
          },
          "AutoDeploymentsEnabled": false,
          "AuthenticationConfiguration": {
            "AccessRoleArn": "${aws_iam_role.apprunner_access.arn}"
          }
        }'
    EOT
  }
}
