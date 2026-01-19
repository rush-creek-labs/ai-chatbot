output "apprunner_service_url" {
  description = "HTTPS URL of the App Runner service"
  value       = "https://${aws_apprunner_service.chatbot.service_url}"
}

output "apprunner_service_arn" {
  description = "ARN of the App Runner service"
  value       = aws_apprunner_service.chatbot.arn
}

output "apprunner_service_id" {
  description = "Service ID for deployments"
  value       = aws_apprunner_service.chatbot.service_id
}

output "ecr_repository_url" {
  description = "ECR repository URL (shared with ECS infrastructure)"
  value       = data.aws_ecr_repository.chatbot.repository_url
}

output "vpc_connector_arn" {
  description = "ARN of the VPC connector"
  value       = aws_apprunner_vpc_connector.chatbot.arn
}

output "deployment_command" {
  description = "Command to trigger a new deployment"
  value       = "aws apprunner start-deployment --service-arn ${aws_apprunner_service.chatbot.arn}"
}

output "update_auth_url_command" {
  description = "Command to update AUTH_URL after initial deployment"
  value       = <<-EOT
    After deployment, update AUTH_URL with:

    aws apprunner update-service \
      --service-arn ${aws_apprunner_service.chatbot.arn} \
      --source-configuration '{
        "ImageRepository": {
          "ImageIdentifier": "${data.aws_ecr_repository.chatbot.repository_url}:latest",
          "ImageRepositoryType": "ECR",
          "ImageConfiguration": {
            "Port": "3000",
            "RuntimeEnvironmentVariables": {
              "NODE_ENV": "production",
              "AWS_REGION": "${var.aws_region}",
              "AUTH_TRUST_HOST": "true",
              "AUTH_URL": "https://${aws_apprunner_service.chatbot.service_url}"
            },
            "RuntimeEnvironmentSecrets": {
              "POSTGRES_URL": "${data.aws_secretsmanager_secret.postgres_url.arn}",
              "AUTH_SECRET": "${data.aws_secretsmanager_secret.auth_secret.arn}"
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
