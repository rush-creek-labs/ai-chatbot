# AWS App Runner Infrastructure

This directory contains Terraform configuration for deploying the AI Chatbot application using AWS App Runner as an alternative to the ECS Fargate deployment in `infrastructure/`.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │      App Runner         │
                    │   (HTTPS automatic)     │
                    │                         │
                    │   ┌─────────────────┐   │
                    │   │   Container     │   │
                    │   │   Port 3000     │   │
                    │   └─────────────────┘   │
                    └───────────┬─────────────┘
                                │
                    ┌───────────┴───────────┐
                    │    VPC Connector      │
                    └───────────┬───────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
    ┌─────────────────┐  ┌────────────┐  ┌──────────────┐
    │ RDS PostgreSQL  │  │  Bedrock   │  │   Secrets    │
    │   (shared)      │  │    API     │  │   Manager    │
    └─────────────────┘  └────────────┘  └──────────────┘
```

## Prerequisites

1. **Existing infrastructure from `infrastructure/`**:
   - ECR repository (`ai-chatbot`)
   - RDS PostgreSQL instance
   - Secrets Manager secrets (`prod/chatbot/postgres-url`, `prod/chatbot/auth-secret`)

2. **Docker image pushed to ECR**:
   ```bash
   # From repository root
   docker build -t ai-chatbot .
   docker tag ai-chatbot:latest <account>.dkr.ecr.us-east-1.amazonaws.com/ai-chatbot:latest
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
   docker push <account>.dkr.ecr.us-east-1.amazonaws.com/ai-chatbot:latest
   ```

3. **Database migrations run** (if not already):
   ```bash
   POSTGRES_URL="postgresql://..." pnpm db:migrate
   ```

## Deployment

### Initial Deployment

```bash
cd infrastructure-v2

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Post-Deployment: Update AUTH_URL

After the initial deployment, you need to update `AUTH_URL` with the generated service URL:

1. Get the service URL from outputs:
   ```bash
   terraform output apprunner_service_url
   ```

2. Update the service configuration (the full command is provided in outputs):
   ```bash
   terraform output -raw update_auth_url_command
   ```

   Or manually:
   ```bash
   aws apprunner update-service \
     --service-arn <service-arn> \
     --source-configuration '{...with AUTH_URL set...}'
   ```

## Triggering Deployments

After pushing a new Docker image to ECR:

```bash
# Get the deployment command from outputs
terraform output -raw deployment_command

# Or directly:
aws apprunner start-deployment --service-arn <service-arn>
```

## Key Differences from ECS Deployment

| Aspect | ECS Fargate | App Runner |
|--------|-------------|------------|
| Load Balancer | ALB (manual) | Built-in |
| HTTPS | CloudFront | Automatic |
| Scaling | Manual config | Automatic |
| VPC | Native | Via VPC Connector |
| Cost | Pay per task | Pay per request + min instance |
| Health Checks | Configurable | Limited options |

## Health Check Configuration

App Runner health checks are configured with maximum allowed values to accommodate Next.js startup time (20-30 seconds):

- **Path**: `/api/health`
- **Interval**: 20 seconds (max allowed)
- **Timeout**: 20 seconds (max allowed)
- **Healthy threshold**: 1
- **Unhealthy threshold**: 20 (max allowed)

**Note**: App Runner limits timeout to 20 seconds maximum. With these settings, the service has approximately 400 seconds (~6.6 minutes) of total grace period before being marked unhealthy (20 checks × 20 second intervals).

## Troubleshooting

### Service stuck in "Operation in progress"

Check CloudWatch logs:
```bash
aws logs tail /apprunner/prod-ai-chatbot --follow
```

### Health checks failing

1. Verify the container starts successfully locally:
   ```bash
   docker run -p 3000:3000 -e NODE_ENV=production ai-chatbot:latest
   curl http://localhost:3000/api/health
   ```

2. Check if the health endpoint responds within 30 seconds

3. Review App Runner service events in the AWS Console

### Database connection issues

Ensure the VPC connector security group allows outbound traffic to RDS:
- The RDS security group (`prod-rds-sg`) must allow inbound PostgreSQL (5432) from the App Runner security group

## Coexistence with ECS

This App Runner deployment can run alongside the ECS Fargate deployment:
- Both use the same ECR repository
- Both connect to the same RDS instance
- Both use the same Secrets Manager secrets
- Each has its own URL endpoint

To switch traffic:
1. Test the App Runner endpoint
2. Update DNS/CloudFront if using custom domain
3. Optionally scale down ECS tasks

## Cleanup

To destroy App Runner resources without affecting ECS:

```bash
cd infrastructure-v2
terraform destroy
```

This will not affect:
- ECR repository
- RDS database
- Secrets Manager secrets
- ECS cluster/service
