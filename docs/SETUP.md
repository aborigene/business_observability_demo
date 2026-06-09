# Complete Setup Guide

This guide will walk you through deploying the entire Dynatrace Business Observability Demo application.

## Prerequisites

### Required Tools
- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm 3.x
- **Podman** (recommended) or Docker — see [Container Tool notes](#container-tool-podman-or-docker) below
- git

### Dynatrace Requirements
- Dynatrace environment (SaaS or Managed)
- **API Token** with permissions:
  - `DataExport`, `ReadConfig`, `WriteConfig`, `InstallerDownload`
  - `entities.read`, `settings.read`, `settings.write`
  - `bizevents.ingest` (for Business Events)
- **PaaS Token** (Data Ingest Token) for OneAgent installation

### Container Tool: Podman or Docker

The build and push scripts auto-detect which tool is available, preferring Podman. You can also set it explicitly:

```bash
export CONTAINER_TOOL=podman   # or docker
```

**Podman on macOS** requires a Linux VM. Initialize it once:
```bash
podman machine init
podman machine start
```

## Architecture Overview

All five tiers run on Kubernetes (EKS). There are no EC2 instances.

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│ Tier 1  │────▶│ Tier 2  │────▶│ Tier 3  │────▶│ Tier 4  │────▶│ Tier 5  │
│ Node.js │     │  Java   │     │    C    │     │ Python  │     │  .NET   │
│  (K8s)  │     │  (K8s)  │     │  (K8s)  │     │  (K8s)  │     │  (K8s)  │
└─────────┘     └─────────┘     └─────────┘     └─────────┘     └────┬────┘
                                                                       │
                                                                ┌──────▼───┐
                                                                │   RDS    │
                                                                │PostgreSQL│
                                                                └──────────┘
```

| Tier | Technology | Port | Dynatrace Mode |
|------|------------|------|----------------|
| **Tier 1** | Node.js Express | 3000 | OneAgent Full-Stack |
| **Tier 2** | Java Spring Boot | 8080 | OneAgent Full-Stack |
| **Tier 3** | C Legacy (binary) | 8000 | OneAgent Full-Stack |
| **Tier 4** | Python FastAPI | 8001 | Business Events API only |
| **Tier 5** | .NET 8 Minimal API | 5000 | OneAgent Full-Stack |

## Step 1: Infrastructure Deployment (Terraform)

### 1.1 Clone Repository
```bash
git clone <repository-url>
cd business_observability_demo
```

### 1.2 Configure Terraform Variables
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
aws_region   = "us-east-1"
project_name = "dynatrace-bo-demo"

# Who is deploying (required by org tagging policy)
created_by = "your.email@company.com"

# Database
db_username = "loanadmin"
db_password = "YourSecurePassword123!"
db_name     = "loandb"

# Dynatrace
dt_env_url    = "https://abc12345.live.dynatrace.com"
dt_paas_token = "dt0c01.YOUR_PAAS_TOKEN"
dt_api_token  = "dt0c01.YOUR_API_TOKEN"
```

### 1.3 VPC Options

**Option A: Create a new VPC (default)**  
No extra configuration needed.

**Option B: Use an existing VPC**
```bash
./scripts/validate-vpc.sh vpc-xxxxxxxxxxxxx us-east-1
```
```hcl
use_existing_vpc            = true
existing_vpc_id             = "vpc-xxxxxxxxxxxxx"
existing_public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]
existing_private_subnet_ids = ["subnet-ccc", "subnet-ddd"]
```

### 1.4 EKS Options

**Option A: Create a new EKS cluster (default)**
```hcl
use_existing_eks    = false
eks_cluster_version = "1.28"
```

**Option B: Use an existing EKS cluster**

Use this when your AWS environment restricts EKS cluster creation (e.g. an org-level SCP). Terraform skips creating the cluster, IAM roles, and node groups entirely.
```hcl
use_existing_eks          = true
existing_eks_cluster_name = "your-cluster-name"
```

### 1.5 Initialize and Deploy
```bash
terraform init
terraform plan
terraform apply   # takes ~5-10 minutes (no EC2 instances to provision)
```

### 1.6 Save RDS Endpoint
After apply, note the RDS endpoint — you'll need it in Step 5:
```bash
terraform output rds_endpoint
```

### 1.7 Configure kubectl
```bash
$(terraform output -raw configure_kubectl_command)
kubectl get nodes
```

## Step 2: Delete Previously Created EC2 Instances

If you had EC2 instances from a previous deployment, clean them up:
```bash
cd scripts
./delete-ec2-instances.sh
```

The script is idempotent — safe to run if the instances are already gone.

## Step 3: Build and Push Container Images

> **ARM Mac users (Apple Silicon):** The build scripts automatically add `--platform linux/amd64`
> to every build. EKS Fargate and standard node groups expect AMD64. Do not remove this flag.
>
> To override: `BUILD_PLATFORM=linux/arm64 ./scripts/build-images.sh`

### 3.1 Login to ECR

**Podman:**
```bash
aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
```

**Docker:**
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
```

### 3.2 Build All Five Images
```bash
cd scripts
./build-images.sh
```

Builds: tier1 (Node.js), tier2 (Java), tier3 (C), tier4 (Python), tier5 (.NET) — all for `linux/amd64`.

### 3.3 Push to ECR
```bash
./push-to-ecr.sh
```

Creates ECR repositories if they don't exist, then pushes all five images.

## Step 4: Install Dynatrace Operator

```bash
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm repo update

helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --create-namespace \
  --set installCRD=true

# Configure credentials and DynaKube
kubectl apply -f k8s/dynatrace-operator/01-secret.yaml   # edit with your tokens first
kubectl apply -f k8s/dynatrace-operator/02-dynakube.yaml # edit with your env URL first

kubectl get pods -n dynatrace   # wait for OneAgent DaemonSet to be running
```

## Step 5: Configure and Deploy Kubernetes Applications

### 5.1 Create Namespace
```bash
kubectl apply -f k8s/namespace/loan-app-namespace.yaml
```

### 5.2 Configure Tier 5 Database Secret

Fill in the RDS endpoint from Step 1.6:
```bash
RDS_ENDPOINT=$(cd infra/terraform && terraform output -raw rds_endpoint)
```

Edit [k8s/tier5/02-secret.yaml](../k8s/tier5/02-secret.yaml) and replace the placeholders:
```yaml
DATABASE_URL: "Host=<RDS_ENDPOINT>;Port=5432;Database=loandb;Username=loanadmin;Password=<YOUR_PASSWORD>"
```

### 5.3 Update Image References

```bash
export ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" k8s/tier1/03-deployment.yaml
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" k8s/tier2/02-deployment.yaml
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" k8s/tier3/02-deployment.yaml
sed -i "s|YOUR_ENVIRONMENT_ID|abc12345|g"     k8s/tier4/02-secret.yaml
sed -i "s|YOUR_API_TOKEN_HERE|your-token|g"   k8s/tier4/02-secret.yaml
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g"  k8s/tier4/03-deployment.yaml
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g"  k8s/tier5/03-deployment.yaml
```

### 5.4 Deploy All Tiers
```bash
kubectl apply -f k8s/tier1/
kubectl apply -f k8s/tier2/
kubectl apply -f k8s/tier3/
kubectl apply -f k8s/tier4/
kubectl apply -f k8s/tier5/

kubectl get pods -n loan-app     # wait for all pods Running
kubectl get svc -n loan-app
```

### 5.5 Get Load Balancer URL
```bash
# Wait for EXTERNAL-IP (may take 2-3 minutes)
export TIER1_URL=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://$TIER1_URL"
```

## Step 6: Verify End-to-End Flow

```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-approved.json
```

Expected response:
```json
{
  "status": "success",
  "decision": "APPROVED",
  "finalScore": 85,
  "approvedAmount": 50000,
  "totalDue": 53250.00
}
```

### Check Logs

```bash
kubectl logs -n loan-app -l app=tier1 --tail=50
kubectl logs -n loan-app -l app=tier2 --tail=50
kubectl logs -n loan-app -l app=tier3 --tail=50
kubectl logs -n loan-app -l app=tier4 --tail=50
kubectl logs -n loan-app -l app=tier5 --tail=50
```

## Step 7: Verify in Dynatrace

1. **Services** — you should see all five tiers discovered automatically
2. **Distributed Traces** — filter by `loan-submission`, traces should span all tiers
3. **Business Events** → filter `event.type == "loan.decision"` for business analytics
4. **Infrastructure** → **Kubernetes** — verify the EKS cluster and all pods

## Troubleshooting

### Pods Not Starting
```bash
kubectl describe pod <pod-name> -n loan-app
kubectl logs <pod-name> -n loan-app
```

### Wrong CPU Architecture (exec format error)
Image was built for the wrong architecture. Rebuild:
```bash
BUILD_PLATFORM=linux/amd64 ./scripts/build-images.sh
./scripts/push-to-ecr.sh
```

### Podman: Permission Denied on ECR Login
```bash
podman machine start
```

### Tier 5 Database Connection Failure
- Check the `DATABASE_URL` in `k8s/tier5/02-secret.yaml` — ensure the RDS endpoint is correct
- Verify the RDS security group allows port 5432 from the VPC CIDR (Terraform handles this automatically)

### OneAgent Issues
```bash
kubectl get pods -n dynatrace
kubectl logs -n dynatrace -l app.kubernetes.io/name=dynatrace-operator
```

## Cleanup

```bash
# Delete all Kubernetes workloads
kubectl delete namespace loan-app
helm uninstall dynatrace-operator -n dynatrace

# Destroy infrastructure (RDS, EKS if created, VPC if created)
cd infra/terraform
terraform destroy
```

## Next Steps

- Review [DEMO.md](DEMO.md) for demonstration scenarios
- See [COST_ALLOCATION.md](COST_ALLOCATION.md) for cost allocation setup
- Load test the application
- Explore Dynatrace dashboards
