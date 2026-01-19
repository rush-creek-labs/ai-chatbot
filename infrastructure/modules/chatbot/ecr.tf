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
