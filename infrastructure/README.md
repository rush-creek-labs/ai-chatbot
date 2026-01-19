# AWS App Runner Infrastructure

This directory contains Terraform configuration for deploying the AI Chatbot application using AWS App Runner.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           App Runner Services           │
                    │  (created per item in apprunner_services) │
                    └─────────────────┬───────────────────────┘
                                      │
                          ┌───────────┴───────────┐
                          │    VPC Connector      │
                          └───────────┬───────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
        ▼                             ▼                             ▼
┌───────────────┐           ┌─────────────────┐           ┌─────────────────┐
│      RDS      │           │  VPC Endpoint   │           │  VPC Endpoint   │
│  PostgreSQL   │           │    Bedrock      │           │ Secrets Manager │
└───────────────┘           └─────────────────┘           └─────────────────┘
```

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.14.3
3. **Docker** installed and running
4. **Bedrock model access** enabled in AWS Console

## Staged Deployment

The infrastructure supports staged deployment via the `apprunner_services` variable:

1. **Phase 1**: Deploy base infrastructure with `apprunner_services = []`
2. **Phase 2**: Run database migrations and push Docker image
3. **Phase 3**: Enable App Runner services with `apprunner_services = ["prod"]`

## Deployment

### Phase 1: Base Infrastructure

```bash
cd infrastructure

# Initialize Terraform
terraform init

# Create terraform.tfvars (do not commit!)
cat > terraform.tfvars << EOF
db_password = "your-secure-database-password"
auth_secret = "$(openssl rand -base64 32)"
apprunner_services = []
EOF

# Deploy base infrastructure
terraform apply
```

This creates:
- ECR repository
- RDS PostgreSQL database
- Secrets Manager secrets
- VPC endpoints (Bedrock, Secrets Manager)
- VPC connector
- Security groups
- IAM roles

### Phase 2: Database Migration & Image Push

```bash
# Get outputs
ECR_URL=$(terraform output -raw ecr_repository_url)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

# Run database migrations
POSTGRES_URL="postgresql://chatbot_admin:YOUR_PASSWORD@$RDS_ENDPOINT/chatbot" pnpm db:migrate

# Build and push Docker image
docker build -t ai-chatbot ..
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
docker tag ai-chatbot:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### Phase 3: Enable App Runner Services

```bash
# Update terraform.tfvars to add services
# apprunner_services = ["prod"]

terraform apply
```

### Phase 4: Update AUTH_URL (Optional)

With `AUTH_TRUST_HOST=true`, NextAuth.js automatically uses the Host header, so `AUTH_URL` is not required. Only set it explicitly if using a custom domain or for security hardening.

```bash
# Get the service URL
terraform output apprunner_service_urls

# Get the update command
terraform output -json update_auth_url_commands | jq -r '.prod'
```

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | `us-east-1` | AWS region |
| `aws_profile` | string | `default` | AWS CLI profile to use |
| `environment` | string | `dev` | Environment prefix |
| `db_password` | string | (required) | RDS database password |
| `auth_secret` | string | (required) | NextAuth.js signing secret |
| `apprunner_services` | list(string) | `[]` | Service names to create |

## Multiple Environments

To create multiple App Runner services:

```hcl
apprunner_services = ["prod", "staging"]
```

Each service gets:
- Independent App Runner service
- Separate auto-scaling configuration
- Dedicated CloudWatch log group
- Unique service URL

## Outputs

| Output | Description |
|--------|-------------|
| `ecr_repository_url` | ECR URL for pushing images |
| `rds_endpoint` | RDS database endpoint |
| `apprunner_service_urls` | Map of service name to HTTPS URL |
| `apprunner_service_arns` | Map of service name to ARN |
| `deployment_commands` | Commands to trigger deployments |
| `update_auth_url_commands` | Commands to update AUTH_URL |

## Triggering Deployments

After pushing a new Docker image:

```bash
# Get deployment command for a specific service
terraform output -json deployment_commands | jq -r '.prod'

# Or directly
aws apprunner start-deployment --service-arn $(terraform output -json apprunner_service_arns | jq -r '.prod')
```

## Known Limitations

1. **No external internet access**: VPC egress blocks external URLs (e.g., avatar.vercel.sh). Add a NAT Gateway (~$32/month) if needed.

2. **Health check timeout**: Maximum 20 seconds. Works with Next.js but at the limit.

## File Structure

```
infrastructure/
├── main.tf           # Provider, locals, data sources
├── variables.tf      # Input variables
├── ecr.tf            # ECR repository
├── rds.tf            # RDS PostgreSQL + Secrets Manager
├── vpc.tf            # VPC endpoints, security groups, connector
├── iam.tf            # IAM roles for App Runner
├── apprunner.tf      # App Runner services (conditional)
├── outputs.tf        # Dynamic outputs
└── README.md         # This file
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This deletes all data including the database.
