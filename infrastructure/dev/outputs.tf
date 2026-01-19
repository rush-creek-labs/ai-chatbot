################################################################################
# Base Infrastructure Outputs (always available)
################################################################################

output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = module.chatbot.ecr_repository_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.chatbot.rds_endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.chatbot.rds_database_name
}

output "vpc_connector_arn" {
  description = "ARN of the VPC connector"
  value       = module.chatbot.vpc_connector_arn
}

################################################################################
# App Runner Service Outputs (dynamic based on apprunner_services)
################################################################################

output "apprunner_service_urls" {
  description = "HTTPS URLs of created App Runner services"
  value       = module.chatbot.apprunner_service_urls
}

output "apprunner_service_arns" {
  description = "ARNs of created App Runner services"
  value       = module.chatbot.apprunner_service_arns
}

output "apprunner_service_ids" {
  description = "Service IDs for deployments"
  value       = module.chatbot.apprunner_service_ids
}

################################################################################
# Deployment Commands
################################################################################

output "deployment_commands" {
  description = "Commands to trigger new deployments for each service"
  value       = module.chatbot.deployment_commands
}

output "update_auth_url_commands" {
  description = "Commands to update AUTH_URL after initial deployment"
  value       = module.chatbot.update_auth_url_commands
}
