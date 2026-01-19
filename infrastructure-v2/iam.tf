################################################################################
# App Runner Access Role (for ECR image pulls)
################################################################################

resource "aws_iam_role" "apprunner_access" {
  name = "${local.name}-apprunner-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

################################################################################
# App Runner Instance Role (for runtime - Bedrock, Secrets Manager)
################################################################################

resource "aws_iam_role" "apprunner_instance" {
  name = "${local.name}-apprunner-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# Bedrock access policy (same permissions as ECS task role)
resource "aws_iam_role_policy" "apprunner_bedrock" {
  name = "${local.name}-bedrock"
  role = aws_iam_role.apprunner_instance.id

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
      },
      {
        # Required for Claude models - verifies AWS Marketplace subscription
        Effect = "Allow"
        Action = [
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe"
        ]
        Resource = "*"
      }
    ]
  })
}

# Secrets Manager read access (for runtime environment secrets)
resource "aws_iam_role_policy" "apprunner_secrets" {
  name = "${local.name}-secrets"
  role = aws_iam_role.apprunner_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          data.aws_secretsmanager_secret.postgres_url.arn,
          data.aws_secretsmanager_secret.auth_secret.arn
        ]
      }
    ]
  })
}
