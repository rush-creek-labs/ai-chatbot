# AWS Deployment Guide

This document describes the AWS deployment architecture for the AI Chatbot using AWS App Runner.

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

- **Compute:** AWS App Runner (containerized Next.js with automatic HTTPS)
- **Database:** Amazon RDS PostgreSQL (db.t3.micro - free tier eligible)
- **AI Models:** Amazon Bedrock (Claude 4.5/4/3.5 via inference profiles, Amazon Nova)
- **Secrets:** AWS Secrets Manager
- **Infrastructure:** Terraform (modular, multi-environment)

## Infrastructure Directory Structure

```
infrastructure/
├── modules/
│   └── chatbot/           # Shared Terraform module
│       ├── main.tf        # Locals, data sources
│       ├── variables.tf   # Module input variables
│       ├── outputs.tf     # Module outputs
│       ├── vpc.tf         # VPC connector, security groups, endpoints
│       ├── ecr.tf         # ECR repository
│       ├── rds.tf         # RDS, Secrets Manager
│       ├── iam.tf         # IAM roles and policies
│       └── apprunner.tf   # App Runner service
├── dev/                   # Dev environment
│   ├── main.tf            # Provider config + module call
│   ├── outputs.tf         # Re-export module outputs
│   └── terraform.tfvars   # Environment-specific values (not committed)
└── sandbox/               # Sandbox environment
    ├── main.tf            # Provider config + module call
    ├── outputs.tf         # Re-export module outputs
    └── terraform.tfvars   # Environment-specific values (not committed)
```

Each environment:
- Has its own Terraform state (stored locally in `.terraform/` by default)
- Can use a different AWS profile via `aws_profile` variable
- Can be deployed independently
- Shares the same module code from `infrastructure/modules/chatbot/`

## Available AI Models

Models are accessed via Amazon Bedrock. Claude models require inference profiles for on-demand usage.

| Model ID | Name | Use Case |
|----------|------|----------|
| `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Claude Sonnet 4.5 | Most intelligent, complex tasks |
| `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Claude Haiku 4.5 | Fast and intelligent |
| `us.anthropic.claude-sonnet-4-20250514-v1:0` | Claude Sonnet 4 | Highly capable reasoning |
| `us.anthropic.claude-haiku-4-20250514-v1:0` | Claude Haiku 4 | Fast, general tasks |
| `us.anthropic.claude-3-5-haiku-20241022-v1:0` | Claude 3.5 Haiku | Fast, simple tasks |
| `us.anthropic.claude-3-5-sonnet-20241022-v2:0` | Claude 3.5 Sonnet | Balanced speed/intelligence |
| `amazon.nova-lite-v1:0` | Amazon Nova Lite | Title generation, simple tasks |
| `amazon.nova-pro-v1:0` | Amazon Nova Pro | Advanced tasks |

**Note:** Claude models use cross-region inference profiles (prefixed with `us.`) rather than direct model IDs. This is required for on-demand invocation in Bedrock.

## Environment Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `POSTGRES_URL` | Database connection string | AWS Secrets Manager |
| `AUTH_SECRET` | NextAuth.js signing secret | AWS Secrets Manager |
| `AUTH_TRUST_HOST` | Trust proxy headers (set to "true") | App Runner env vars |
| `AUTH_URL` | Public-facing URL (optional with AUTH_TRUST_HOST) | App Runner env vars |
| `AWS_REGION` | AWS region (default: us-east-1) | App Runner env vars |

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.14.3
3. **Docker** installed and running
4. **Bedrock model access** enabled in AWS Console

### Enable Bedrock Model Access

Before deploying, you must enable access to the required models:

1. Go to AWS Console > Amazon Bedrock > Model access
2. Request access to the models you want to use:
   - `anthropic.claude-sonnet-4-5-20250929-v1:0` (Claude Sonnet 4.5)
   - `anthropic.claude-haiku-4-5-20251001-v1:0` (Claude Haiku 4.5)
   - `anthropic.claude-sonnet-4-20250514-v1:0` (Claude Sonnet 4)
   - `anthropic.claude-haiku-4-20250514-v1:0` (Claude Haiku 4)
   - `anthropic.claude-3-5-sonnet-20241022-v2:0` (Claude 3.5 Sonnet)
   - `anthropic.claude-3-5-haiku-20241022-v1:0` (Claude 3.5 Haiku)
   - `amazon.nova-pro-v1:0` (Amazon Nova Pro)
   - `amazon.nova-lite-v1:0` (Amazon Nova Lite)
3. Wait for approval (usually instant for Nova, may take time for Claude)

## Staged Deployment

The infrastructure supports staged deployment via the `apprunner_services` variable:

1. **Phase 1**: Deploy base infrastructure with `apprunner_services = []`
2. **Phase 2**: Run database migrations and push Docker image
3. **Phase 3**: Enable App Runner services with `apprunner_services = ["prod"]`

This approach ensures the database is migrated and the Docker image is ready before App Runner tries to start.

## Deployment

Choose your target environment (`dev` or `sandbox`) and follow the steps below.

### Phase 1: Base Infrastructure

```bash
# Choose your environment
cd infrastructure/dev      # or infrastructure/sandbox

# Initialize Terraform
terraform init

# Create terraform.tfvars (do not commit this file!)
cat > terraform.tfvars << EOF
db_password = "your-secure-database-password"
auth_secret = "$(openssl rand -base64 32)"
apprunner_services = []
# aws_profile = "sandbox"  # Uncomment if using a different AWS profile
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
# Set your environment (dev or sandbox)
ENV=dev

# Get outputs (from project root)
ECR_URL=$(cd infrastructure/$ENV && terraform output -raw ecr_repository_url)
RDS_ENDPOINT=$(cd infrastructure/$ENV && terraform output -raw rds_endpoint)

# Run database migrations (replace YOUR_PASSWORD with your db_password)
POSTGRES_URL="postgresql://chatbot_admin:YOUR_PASSWORD@$RDS_ENDPOINT/chatbot" pnpm db:migrate

# Build and push Docker image
docker build -t ai-chatbot .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
docker tag ai-chatbot:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### Phase 3: Enable App Runner Services

```bash
# Update terraform.tfvars to add services
# apprunner_services = ["prod"]

cd infrastructure/$ENV && terraform apply
```

### Phase 4: Update AUTH_URL (Optional)

With `AUTH_TRUST_HOST=true`, NextAuth.js automatically uses the Host header from incoming requests. This means **Phase 4 is optional** if authentication is working correctly.

You may want to explicitly set `AUTH_URL` if:
- You're using a custom domain
- You want to hardcode the URL for security hardening

```bash
# Get the service URL (from project root)
cd infrastructure/$ENV && terraform output apprunner_service_urls

# Get the update command
cd infrastructure/$ENV && terraform output -json update_auth_url_commands | jq -r '.prod'

# Run the update command (copy and execute the output)
```

### Verify Deployment

```bash
# Test health check
curl https://<service-url>/api/health
```

## Updating the Application

To deploy updates after the initial setup:

```bash
# Set your environment (dev or sandbox)
ENV=dev

# Build new image (from project root)
docker build -t ai-chatbot .

# Tag and push
ECR_URL=$(cd infrastructure/$ENV && terraform output -raw ecr_repository_url)
docker tag ai-chatbot:latest $ECR_URL:latest
docker push $ECR_URL:latest

# Trigger new deployment
cd infrastructure/$ENV && terraform output -json deployment_commands | jq -r '.prod'
# Or directly:
aws apprunner start-deployment --service-arn $(cd infrastructure/$ENV && terraform output -json apprunner_service_arns | jq -r '.prod')
```

## Multiple Environments

To create multiple App Runner services (e.g., prod and staging):

```hcl
apprunner_services = ["prod", "staging"]
```

Each service gets:
- Independent App Runner service
- Separate auto-scaling configuration
- Dedicated CloudWatch log group
- Unique service URL

All services share the same:
- ECR repository (use different image tags if needed)
- RDS PostgreSQL database
- Secrets Manager secrets
- VPC connector and endpoints

## Cost Breakdown

| Service | Free Tier | Post-Free-Tier |
|---------|-----------|----------------|
| App Runner | None | ~$5-25/month (scales to zero) |
| VPC Endpoints (Bedrock + Secrets Manager) | None | ~$14/month |
| RDS PostgreSQL | 750 hours/month (year 1) | ~$15-20/month |
| Bedrock | Pay-per-token | ~$5-50/month |
| Secrets Manager | N/A | ~$1/month |

**Estimated monthly cost:** ~$40-110/month (varies with usage)

## Differences from Vercel Deployment

| Feature | Vercel | AWS |
|---------|--------|-----|
| AI Provider | Vercel AI Gateway | Amazon Bedrock |
| File Uploads | Vercel Blob | Disabled |
| Resumable Streams | Redis | Disabled |
| Geolocation | @vercel/functions | Not available |

## Known Limitations

### No External Internet Access

When App Runner uses VPC egress (`egress_type = "VPC"`), all outbound traffic goes through the VPC connector. The infrastructure includes VPC endpoints for AWS services, but **external internet resources are not accessible** without a NAT Gateway (~$32/month).

This means:
- Bedrock API calls work (via VPC endpoint)
- Secrets Manager works (via VPC endpoint)
- RDS database works (within VPC)
- External URLs like `avatar.vercel.sh` will timeout

**Impact:** Avatar images from external sources won't load (non-critical, cosmetic only). The core application functionality is unaffected.

**To enable external internet access**, add a NAT Gateway to the infrastructure. This is not included by default due to cost.

### AUTH_URL (Optional)

With `AUTH_TRUST_HOST=true`, NextAuth.js automatically derives the URL from the Host header, so `AUTH_URL` is not required. You only need to set it explicitly if using a custom domain or for security hardening.

### Health Check Timeout

App Runner limits health check timeout to 20 seconds maximum. The configuration maximizes all timeout values to provide ~400 seconds of grace period for Next.js startup:

```hcl
health_check_configuration {
  protocol            = "HTTP"
  path                = "/api/health"
  interval            = 20  # seconds between checks (max allowed)
  timeout             = 20  # wait 20s for response (max allowed)
  healthy_threshold   = 1   # 1 success = healthy
  unhealthy_threshold = 20  # 20 failures before unhealthy (max allowed)
}
```

### App Runner Availability Zone Support

App Runner does not support all availability zones. In us-east-1, `use1-az3` is not supported. The Terraform configuration automatically filters subnets to supported AZs:

```hcl
locals {
  apprunner_supported_azs = ["use1-az1", "use1-az2", "use1-az4", "use1-az5", "use1-az6"]
}
```

---

## Troubleshooting

### Bedrock Access Denied

**Error:** `AccessDeniedException: You don't have access to the model`

**Solution:**
1. Ensure models are enabled in AWS Console > Bedrock > Model access
2. For Claude models, use inference profile IDs (prefixed with `us.`) not direct model IDs
3. Check that the App Runner instance role has the correct Bedrock permissions

### Bedrock Inference Profile Required

**Error:** `Invocation of model ID anthropic.claude-* with on-demand throughput isn't supported`

**Solution:** Use inference profile model IDs (prefixed with `us.`):
- Wrong: `anthropic.claude-3-5-haiku-20241022-v1:0`
- Correct: `us.anthropic.claude-3-5-haiku-20241022-v1:0`

### Claude Models Access Denied (Marketplace)

**Error:** `Model access is denied due to IAM user or service role is not authorized to perform the required AWS Marketplace actions (aws-marketplace:ViewSubscriptions, aws-marketplace:Subscribe)`

**Cause:** Claude models in Bedrock require AWS Marketplace subscription verification. The IAM role needs marketplace permissions.

**Solution:** Ensure the App Runner instance role includes marketplace permissions:
```hcl
{
  Effect = "Allow"
  Action = [
    "aws-marketplace:ViewSubscriptions",
    "aws-marketplace:Subscribe"
  ]
  Resource = "*"
}
```

This is already included in the infrastructure IAM policies. If you see this error:
1. Run `terraform apply` to update IAM policies
2. Wait 5 minutes for IAM propagation
3. Trigger deployment with `aws apprunner start-deployment --service-arn <arn>`

### AWS Credentials Not Found

**Error:** `AWS SigV4 authentication requires AWS credentials`

**Solution:** The application must use the container credentials provider. Ensure `providers.ts` includes:
```typescript
import { fromContainerMetadata, fromEnv } from "@aws-sdk/credential-providers";

const bedrock = createAmazonBedrock({
  region: process.env.AWS_REGION || "us-east-1",
  credentialProvider: async () => {
    try {
      return await fromContainerMetadata()();
    } catch {
      return await fromEnv()();
    }
  },
});
```

### NextAuth UntrustedHost Error

**Error:** `UntrustedHost: Host must be trusted`

**Solution:** Set `AUTH_TRUST_HOST=true` environment variable. This is required when running behind a load balancer or reverse proxy.

### Database Connection Failed

**Error:** `Connection refused` or `timeout`

**Solution:**
1. Check RDS security group allows connections from App Runner VPC connector
2. Verify `POSTGRES_URL` secret contains correct connection string
3. Ensure RDS instance is running
4. For initial setup, RDS is publicly accessible - verify your IP can connect for migrations

### Health Check Failing

**Error:** App Runner service unhealthy

**Solution:**
1. Verify `/api/health` endpoint returns 200 OK
2. Check that `proxy.ts` allows `/api/health` without authentication:
   ```typescript
   if (pathname.startsWith("/api/auth") || pathname.startsWith("/api/health")) {
     return NextResponse.next();
   }
   ```
3. Check CloudWatch logs: `/apprunner/<service-name>`
4. Ensure all environment variables are set correctly

### Docker Build Fails

**Error:** Build errors during `pnpm install`

**Solution:**
1. Ensure `pnpm-lock.yaml` is committed and up to date
2. Run `pnpm install` locally first to verify dependencies
3. Check Node.js version matches Dockerfile (20-alpine)

## Destroying Infrastructure

To tear down all AWS resources for an environment:

```bash
# Set your environment (dev or sandbox)
ENV=dev

cd infrastructure/$ENV
terraform destroy
```

**Warning:** This will delete all data including the database. Export any data you need first.

## Security Recommendations

1. **Disable public RDS access** after initial setup by setting `publicly_accessible = false`
2. **Enable deletion protection** on RDS for production: `deletion_protection = true`
3. **Restrict RDS security group** to only allow connections from VPC connector security group
4. **Rotate secrets** regularly using AWS Secrets Manager rotation
5. **Enable CloudWatch alarms** for monitoring and alerting
