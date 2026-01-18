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
- **AI Models:** Amazon Bedrock (Claude 3.5 via inference profiles, Amazon Nova)
- **Infrastructure:** Terraform

## Available AI Models

Models are accessed via Amazon Bedrock. Claude models require inference profiles for on-demand usage.

| Model ID | Name | Use Case |
|----------|------|----------|
| `us.anthropic.claude-3-5-haiku-20241022-v1:0` | Claude 3.5 Haiku | Fast responses, artifacts |
| `us.anthropic.claude-3-5-sonnet-20241022-v2:0` | Claude 3.5 Sonnet | Complex reasoning |
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
2. Request access to:
   - `anthropic.claude-3-5-sonnet-20241022-v2:0`
   - `anthropic.claude-3-5-haiku-20241022-v1:0`
   - `amazon.nova-pro-v1:0`
   - `amazon.nova-lite-v1:0`
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

| Service | Free Tier | Post-Free-Tier |
|---------|-----------|----------------|
| CloudFront | 1 TB/month (year 1) | ~$1-5/month |
| ECS Fargate | None | ~$10-30/month |
| ALB | None | ~$16-20/month |
| RDS PostgreSQL | 750 hours/month (year 1) | ~$15-20/month |
| Bedrock | Pay-per-token | ~$5-50/month |
| Secrets Manager | N/A | ~$1/month |

**Estimated monthly cost:** ~$50-125/month (varies with usage)

## Differences from Vercel Deployment

| Feature | Vercel | AWS |
|---------|--------|-----|
| AI Provider | Vercel AI Gateway | Amazon Bedrock |
| File Uploads | Vercel Blob | Disabled |
| Resumable Streams | Redis | Disabled |
| Geolocation | @vercel/functions | Not available |

---

## Deployment Options Evaluated

During development, we evaluated several AWS compute options. This section documents what we tried and the issues encountered.

### Option 1: AWS App Runner (Not Recommended)

**Status:** Failed - Health checks never passed

App Runner was the initial choice due to its simplicity and managed infrastructure. However, we encountered persistent health check failures that could not be resolved.

**Issues encountered:**

1. **Health check timing:** The Next.js application takes 20-30 seconds to start. App Runner's health checks would begin before the app was ready, marking the service as unhealthy.

2. **Health check configuration limitations:** Even with increased timeouts and unhealthy thresholds, the service never became healthy.

3. **VPC Connector complications:** Initially configured with VPC egress for database access, but this added complexity without solving the health check issue.

4. **Proxy middleware interference:** The NextAuth.js middleware was intercepting health check requests and redirecting to `/api/auth/guest`. This was fixed by adding a bypass in `proxy.ts`, but health checks still failed.

5. **Service stuck in "In progress":** After 10+ minutes, the App Runner service would remain in "Operation in progress" state with no clear error messages, making debugging difficult.

**Configuration attempted:**
```hcl
health_check_configuration {
  path                = "/api/health"
  protocol            = "HTTP"
  timeout             = 10
  interval            = 10
  healthy_threshold   = 1
  unhealthy_threshold = 20  # Increased to allow more startup time
}
```

**Conclusion:** App Runner's health check behavior is not well-suited for Next.js applications with longer startup times. The lack of detailed logging during health check failures made debugging nearly impossible.

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

### Option 3: ECS Fargate with ALB (Recommended)

**Status:** Working

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
