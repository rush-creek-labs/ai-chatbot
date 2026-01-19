# AWS Deployment Guide

This document describes the AWS deployment architecture for the AI Chatbot.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│       ALB       │────▶│   ECS Fargate   │────▶│  RDS PostgreSQL │
│ (Load Balancer) │     │  (Next.js app)  │     │   (db.t3.micro) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                │
                                │  IAM Role             ┌─────────────────┐
                                └──────────────────────▶│ Amazon Bedrock  │
                                                        │ (Claude, Nova)  │
                                                        └─────────────────┘
```

- **CDN/HTTPS:** Amazon CloudFront (provides HTTPS with default certificate)
- **Compute:** AWS ECS Fargate (containerized Next.js)
- **Load Balancer:** Application Load Balancer (ALB)
- **Database:** Amazon RDS PostgreSQL (db.t3.micro - free tier eligible)
- **AI Models:** Amazon Bedrock (Claude 4.5/4/3.5 via inference profiles, Amazon Nova)
- **Infrastructure:** Terraform

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
| `AUTH_TRUST_HOST` | Trust proxy headers (set to "true") | ECS Task Definition |
| `AUTH_URL` | Public-facing URL (e.g., CloudFront domain) | ECS Task Definition |
| `AWS_REGION` | AWS region (default: us-east-1) | ECS Task Definition |

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

## Deployment

### Step 1: Deploy Infrastructure

```bash
cd infrastructure

# Initialize Terraform
terraform init

# Create terraform.tfvars with your secrets (do not commit this file!)
cat > terraform.tfvars << EOF
aws_region   = "us-east-1"
environment  = "prod"
db_password  = "your-secure-database-password"
auth_secret  = "$(openssl rand -base64 32)"
EOF

# Review the plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Step 2: Run Database Migrations

After the infrastructure is created, run migrations before pushing the Docker image:

```bash
# Get the RDS endpoint from terraform output
RDS_ENDPOINT=$(cd infrastructure && terraform output -raw rds_endpoint)

# Run migrations (replace password with your db_password)
POSTGRES_URL="postgresql://chatbot_admin:YOUR_PASSWORD@$RDS_ENDPOINT/chatbot" pnpm db:migrate
```

### Step 3: Build and Push Docker Image

```bash
# Get ECR URL from terraform output
ECR_URL=$(cd infrastructure && terraform output -raw ecr_repository_url)

# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

# Build the Docker image
docker build -t ai-chatbot .

# Tag for ECR
docker tag ai-chatbot:latest $ECR_URL:latest

# Push to ECR
docker push $ECR_URL:latest
```

### Step 4: Force ECS Deployment

After pushing the image, force ECS to deploy the new version:

```bash
# Get cluster and service names
CLUSTER=$(cd infrastructure && terraform output -raw ecs_cluster_name)
SERVICE=$(cd infrastructure && terraform output -raw ecs_service_name)

# Force new deployment
aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment
```

### Step 5: Verify Deployment

```bash
# Get the app URL
cd infrastructure && terraform output app_url

# Test health check
curl http://<alb-dns-name>/api/health
```

## Updating the Application

To deploy updates:

```bash
# Build new image
docker build -t ai-chatbot .

# Tag and push
ECR_URL=$(cd infrastructure && terraform output -raw ecr_repository_url)
docker tag ai-chatbot:latest $ECR_URL:latest
docker push $ECR_URL:latest

# Force new deployment
CLUSTER=$(cd infrastructure && terraform output -raw ecs_cluster_name)
SERVICE=$(cd infrastructure && terraform output -raw ecs_service_name)
aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment
```

## Cost Breakdown

### ECS Fargate (`infrastructure/`)

| Service | Free Tier | Post-Free-Tier |
|---------|-----------|----------------|
| CloudFront | 1 TB/month (year 1) | ~$1-5/month |
| ECS Fargate | None | ~$10-30/month |
| ALB | None | ~$16-20/month |
| RDS PostgreSQL | 750 hours/month (year 1) | ~$15-20/month |
| Bedrock | Pay-per-token | ~$5-50/month |
| Secrets Manager | N/A | ~$1/month |

**Estimated monthly cost:** ~$50-125/month (varies with usage)

### App Runner (`infrastructure-v2/`)

| Service | Free Tier | Post-Free-Tier |
|---------|-----------|----------------|
| App Runner | None | ~$5-25/month (scales to zero) |
| VPC Endpoints (Bedrock + Secrets Manager) | None | ~$14/month |
| RDS PostgreSQL | 750 hours/month (year 1) | ~$15-20/month |
| Bedrock | Pay-per-token | ~$5-50/month |
| Secrets Manager | N/A | ~$1/month |

**Estimated monthly cost:** ~$40-110/month (lower than ECS due to no ALB/CloudFront)

## Differences from Vercel Deployment

| Feature | Vercel | AWS |
|---------|--------|-----|
| AI Provider | Vercel AI Gateway | Amazon Bedrock |
| File Uploads | Vercel Blob | Disabled |
| Resumable Streams | Redis | Disabled |
| Geolocation | @vercel/functions | Not available |

---

## Deployment Options Evaluated

During development, we evaluated several AWS compute options. **Two options are now working:**

| Option | Infrastructure | Status | Best For |
|--------|---------------|--------|----------|
| **ECS Fargate + ALB** | `infrastructure/` | Recommended | Production, full control |
| **App Runner** | `infrastructure-v2/` | Alternative | Simplicity, lower cost |

Both deployments can run simultaneously and share the same ECR repository, RDS database, and Secrets Manager secrets.

### Option 1: AWS App Runner (Alternative - Working)

**Status:** Working - Service becomes healthy with proper configuration

App Runner provides a simpler, fully managed alternative to ECS Fargate. After initial failures with health checks, we resolved the issues by maximizing health check timeouts and filtering subnets to App Runner-supported availability zones.

**Infrastructure location:** `infrastructure-v2/`

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │      App Runner         │
                    │   (HTTPS automatic)     │
                    │      Port 3000          │
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
    │ RDS PostgreSQL  │  │VPC Endpoint│  │ VPC Endpoint │
    │   (shared)      │  │  Bedrock   │  │Secrets Mgr   │
    └─────────────────┘  └────────────┘  └──────────────┘
```

**Note:** VPC endpoints are required because App Runner with VPC egress cannot reach AWS services via public internet without a NAT Gateway.

**Key configuration that made it work:**

1. **Maximized health check timeouts:** App Runner limits timeout to 20 seconds max. By using max values for all parameters, we provide ~400 seconds of grace period for Next.js startup:
   ```hcl
   health_check_configuration {
     path                = "/api/health"
     protocol            = "HTTP"
     timeout             = 20  # Max allowed (was 10)
     interval            = 20  # Max allowed (was 10)
     healthy_threshold   = 1
     unhealthy_threshold = 20  # Max allowed - gives 20 × 20 = 400s grace period
   }
   ```

2. **Filtered subnets for VPC Connector:** App Runner does NOT support all availability zones. In us-east-1, `use1-az3` is not supported. The Terraform filters subnets:
   ```hcl
   locals {
     apprunner_supported_azs = ["use1-az1", "use1-az2", "use1-az4", "use1-az5", "use1-az6"]
   }

   # Filter subnets to only those in App Runner supported AZs
   locals {
     apprunner_subnet_ids = [
       for subnet in data.aws_subnet.default : subnet.id
       if contains(local.apprunner_supported_azs, subnet.availability_zone_id)
     ]
   }
   ```

3. **Reuses existing infrastructure:** References ECR repository and Secrets Manager secrets from `infrastructure/` via data sources, avoiding duplication.

**Deployment:**
```bash
cd infrastructure-v2
terraform init
terraform plan
terraform apply

# After deployment, get the service URL
terraform output apprunner_service_url

# Trigger new deployments after pushing to ECR
aws apprunner start-deployment --service-arn $(terraform output -raw apprunner_service_arn)
```

**Advantages over ECS Fargate:**
- Simpler setup (no ALB, fewer resources)
- Automatic HTTPS (no CloudFront needed)
- Automatic scaling built-in
- Lower base cost when idle

**Trade-offs:**
- Less control over networking
- Health check timeout limited to 20 seconds
- Limited AZ support requires subnet filtering
- Debugging is harder (less logging visibility)

**Previous issues (now resolved):**
- Health check failures → Fixed with maximized timeouts
- VPC Connector AZ errors → Fixed by filtering to supported AZs
- Proxy middleware interference → Already fixed in `proxy.ts` with `/api/health` bypass
- Bedrock connection timeouts → Fixed with VPC endpoint for `bedrock-runtime`

**Known limitation - No external internet access:**

When App Runner uses `egress_type = "VPC"`, all outbound traffic goes through the VPC connector. The infrastructure includes VPC endpoints for AWS services (Bedrock, Secrets Manager), but **external internet resources are not accessible** without a NAT Gateway (~$32/month).

This means:
- ✅ Bedrock API calls work (via VPC endpoint)
- ✅ Secrets Manager works (via VPC endpoint)
- ✅ RDS database works (within VPC)
- ❌ External URLs like `avatar.vercel.sh` will timeout

**Impact:** Avatar images from external sources won't load (non-critical, cosmetic only). The core application functionality is unaffected.

**To enable external internet access**, add a NAT Gateway to the infrastructure. This is not included by default due to cost.

### Option 2: ECS Express (Not Recommended)

**Status:** Failed - Terraform management issues

ECS Express is a newer, simplified ECS deployment option that AWS manages behind the scenes. The application successfully deployed and became healthy, but we encountered critical issues with infrastructure management.

**Issues encountered:**

1. **Service replacement takes hours:** When making configuration changes, Terraform attempts to replace the ECS Express service. AWS's internal management of ECS Express resources causes deletions to take 2-4+ hours.

2. **Terraform state inconsistencies:** The AWS provider reported "inconsistent result after apply" errors when updating environment variables. The API would reorder environment variable lists, causing state mismatches.
   ```
   Error: Provider produced inconsistent result after apply
   .primary_container[0].environment[0].name: was "NODE_ENV", but now "AUTH_TRUST_HOST"
   ```

3. **Cannot force new deployments easily:** Unlike standard ECS, forcing a new deployment required waiting for the full service replacement cycle.

4. **Module compatibility issues:** The `terraform-aws-modules/ecs` module's `express-service` submodule had compatibility issues with AWS provider v6, requiring specific attribute names that weren't well-documented:
   - `cluster_name` vs `name`
   - `fargate_capacity_providers` vs `cluster_capacity_providers`
   - `auto_scaling_metric` must be `AVERAGE_CPU` not `AverageCPUUtilization`

5. **Limited control:** AWS manages many resources internally (load balancer, target groups, etc.), making it difficult to customize health check settings or networking.

**Conclusion:** ECS Express is too new and has significant issues with Terraform lifecycle management. The inability to quickly iterate on configuration changes makes it unsuitable for active development.

### Option 3: ECS Fargate with ALB (Recommended - Primary)

**Status:** Working - Production recommended

Standard ECS Fargate with an Application Load Balancer provides full control over all resources and reliable Terraform management.

**Advantages:**
- Full control over health check configuration
- Standard ECS deployment model with predictable behavior
- Quick service updates via `aws ecs update-service --force-new-deployment`
- Native AWS resources without module compatibility issues
- Clear separation of concerns (cluster, service, task definition, ALB, target groups)

**Trade-offs:**
- More Terraform code to maintain
- Slightly higher cost due to ALB (~$16/month)
- Manual configuration of IAM roles and security groups

---

## Troubleshooting

### Bedrock Access Denied

**Error:** `AccessDeniedException: You don't have access to the model`

**Solution:**
1. Ensure models are enabled in AWS Console > Bedrock > Model access
2. For Claude models, use inference profile IDs (prefixed with `us.`) not direct model IDs
3. Check that the ECS task role has the correct Bedrock permissions

### Bedrock Inference Profile Required

**Error:** `Invocation of model ID anthropic.claude-* with on-demand throughput isn't supported`

**Solution:** Use inference profile model IDs:
- ❌ `anthropic.claude-3-5-haiku-20241022-v1:0`
- ✅ `us.anthropic.claude-3-5-haiku-20241022-v1:0`

### Claude Models Access Denied (Marketplace)

**Error:** `Model access is denied due to IAM user or service role is not authorized to perform the required AWS Marketplace actions (aws-marketplace:ViewSubscriptions, aws-marketplace:Subscribe)`

**Cause:** Claude models in Bedrock require AWS Marketplace subscription verification. The IAM role needs marketplace permissions.

**Solution:** Ensure the task/instance role includes marketplace permissions:
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

This is already included in both `infrastructure/` and `infrastructure-v2/` IAM policies. If you see this error:
1. Run `terraform apply` to update IAM policies
2. Wait 5 minutes for IAM propagation
3. For ECS: Force a new deployment with `aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment`
4. For App Runner: Trigger deployment with `aws apprunner start-deployment --service-arn <arn>`

### AWS Credentials Not Found in ECS

**Error:** `AWS SigV4 authentication requires AWS credentials`

**Solution:** The application must use the ECS container credentials provider. Ensure `providers.ts` includes:
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

**Solution:** Set `AUTH_TRUST_HOST=true` environment variable in the ECS task definition. This is required when running behind a load balancer where the internal hostname differs from the public URL.

### Database Connection Failed

**Error:** `Connection refused` or `timeout`

**Solution:**
1. Check RDS security group allows connections from ECS security group
2. Verify `POSTGRES_URL` secret contains correct connection string
3. Ensure RDS instance is running
4. For initial setup, RDS is publicly accessible - verify your IP can connect

### Health Check Failing

**Error:** ECS tasks failing health checks

**Solution:**
1. Verify `/api/health` endpoint returns 200 OK
2. Check that `proxy.ts` allows `/api/health` without authentication:
   ```typescript
   if (pathname.startsWith("/api/auth") || pathname.startsWith("/api/health")) {
     return NextResponse.next();
   }
   ```
3. Check CloudWatch logs: `/ecs/<service-name>`
4. Ensure all environment variables are set correctly

### ERR_TOO_MANY_REDIRECTS (Redirect Loop)

**Error:** Browser shows `ERR_TOO_MANY_REDIRECTS` when accessing the application

**Cause:** Cookie name mismatch between NextAuth session creation and token retrieval. This happens because:
1. CloudFront uses `origin_protocol_policy = "http-only"` to connect to ALB
2. CloudFront sets `x-forwarded-proto: http` (the origin protocol, not the viewer protocol)
3. NextAuth creates secure cookies based on `AUTH_URL=https://...`
4. But token retrieval looks for non-secure cookies based on `x-forwarded-proto: http`

**Solution:** The `proxy.ts` middleware must detect HTTPS based on `AUTH_URL` when set:
```typescript
const authUrl = process.env.AUTH_URL;
const forwardedProto = request.headers.get("x-forwarded-proto");
const isHttps = authUrl?.startsWith("https://") ||
                forwardedProto === "https" ||
                request.nextUrl.protocol === "https:";

const token = await getToken({
  req: request,
  secret: process.env.AUTH_SECRET,
  secureCookie: isHttps,
});
```

This ensures the cookie name matches what NextAuth created, regardless of CloudFront's internal protocol handling.

### Docker Build Fails

**Error:** Build errors during `pnpm install`

**Solution:**
1. Ensure `pnpm-lock.yaml` is committed and up to date
2. Run `pnpm install` locally first to verify dependencies
3. Check Node.js version matches Dockerfile (20-alpine)

## Destroying Infrastructure

To tear down all AWS resources:

```bash
cd infrastructure
terraform destroy
```

**Warning:** This will delete all data including the database. Export any data you need first.

## Security Recommendations

1. **Disable public RDS access** after initial setup by setting `publicly_accessible = false`
2. **Enable deletion protection** on RDS for production: `deletion_protection = true`
3. **Restrict RDS security group** to only allow connections from ECS security group
4. **Add HTTPS** by attaching an ACM certificate to the ALB
5. **Rotate secrets** regularly using AWS Secrets Manager rotation
6. **Enable CloudWatch alarms** for monitoring and alerting
