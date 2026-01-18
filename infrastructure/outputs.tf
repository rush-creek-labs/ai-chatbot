output "app_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.chatbot.dns_name}"
}

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

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.chatbot.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for the ECS service"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.chatbot.dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.chatbot.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.chatbot.id
}

output "app_url_https" {
  description = "HTTPS URL via CloudFront"
  value       = "https://${aws_cloudfront_distribution.chatbot.domain_name}"
}
