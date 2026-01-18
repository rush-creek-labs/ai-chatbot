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
  name         = "${var.environment}-ai-chatbot"
  service_name = "${var.environment}-ai-chatbot-v2"
  tags = {
    Name        = local.name
    Environment = var.environment
  }
}

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

################################################################################
# ECR Repository
################################################################################

resource "aws_ecr_repository" "chatbot" {
  name                 = "ai-chatbot"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

################################################################################
# RDS PostgreSQL (Free Tier - db.t3.micro)
################################################################################

resource "aws_db_instance" "postgres" {
  identifier        = "${var.environment}-chatbot-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "chatbot"
  username = "chatbot_admin"
  password = var.db_password

  publicly_accessible    = true
  skip_final_snapshot    = true
  deletion_protection    = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = false
  backup_retention_period = 7

  tags = local.tags
}

################################################################################
# Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "postgres_url" {
  name                    = "${var.environment}/chatbot/postgres-url"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "postgres_url" {
  secret_id     = aws_secretsmanager_secret.postgres_url.id
  secret_string = "postgresql://${aws_db_instance.postgres.username}:${var.db_password}@${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}"
}

resource "aws_secretsmanager_secret" "auth_secret" {
  name                    = "${var.environment}/chatbot/auth-secret"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "auth_secret" {
  secret_id     = aws_secretsmanager_secret.auth_secret.id
  secret_string = var.auth_secret
}

################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "main" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

################################################################################
# ECS Task Definition
################################################################################

resource "aws_ecs_task_definition" "chatbot" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "chatbot"
      image     = "${aws_ecr_repository.chatbot.repository_url}:latest"
      essential = true
      cpu       = 1024
      memory    = 2048

      portMappings = [
        {
          name          = "http"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AUTH_TRUST_HOST", value = "true" },
        { name = "AUTH_URL", value = "https://${aws_cloudfront_distribution.chatbot.domain_name}" }
      ]

      secrets = [
        { name = "POSTGRES_URL", valueFrom = aws_secretsmanager_secret.postgres_url.arn },
        { name = "AUTH_SECRET", valueFrom = aws_secretsmanager_secret.auth_secret.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}

################################################################################
# ECS Service
################################################################################

resource "aws_ecs_service" "chatbot" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.chatbot.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.chatbot.arn
    container_name   = "chatbot"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]

  tags = local.tags
}

################################################################################
# IAM Roles
################################################################################

# ECS Task Execution Role (for pulling images, logging, secrets)
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${local.name}-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.postgres_url.arn,
          aws_secretsmanager_secret.auth_secret.arn
        ]
      }
    ]
  })
}

# ECS Task Role (for application to call AWS services)
resource "aws_iam_role" "ecs_task" {
  name = "${local.name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name = "${local.name}-bedrock"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          # Amazon Nova models (direct access)
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-*",
          # Cross-region inference profiles for Claude
          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-*",
          # Underlying Claude foundation models (cross-region inference can route to any US region)
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*",
          "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-*",
          "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-*"
        ]
      }
    ]
  })
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name}"
  retention_in_days = 14

  tags = local.tags
}

################################################################################
# Application Load Balancer
################################################################################

resource "aws_lb" "chatbot" {
  name               = "${var.environment}-chatbot-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = local.tags
}

resource "aws_lb_target_group" "chatbot" {
  name        = "${var.environment}-chatbot-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.chatbot.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chatbot.arn
  }

  tags = local.tags
}

################################################################################
# CloudFront Distribution
################################################################################

resource "aws_cloudfront_distribution" "chatbot" {
  enabled             = true
  comment             = "${local.name} CloudFront Distribution"
  default_root_object = ""
  price_class         = "PriceClass_100" # US, Canada, Europe only - cheapest option

  origin {
    domain_name = aws_lb.chatbot.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # ALB is HTTP only
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    # Don't cache - forward everything to origin for dynamic content
    forwarded_values {
      query_string = true
      headers      = ["*"] # Forward all headers for auth cookies

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache static assets
  ordered_cache_behavior {
    path_pattern     = "/_next/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400    # 1 day
    max_ttl                = 31536000 # 1 year
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "ecs" {
  name        = "${var.environment}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow traffic from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL from anywhere (ECS + migrations)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}
