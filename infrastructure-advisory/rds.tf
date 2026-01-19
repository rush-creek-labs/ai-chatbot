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
