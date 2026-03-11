# Complete Setup Guide

This guide will walk you through deploying the entire Dynatrace Business Observability Demo application.

## Prerequisites

### Required Tools
- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm 3.x
- Docker
- git

### Dynatrace Requirements
- Dynatrace environment (SaaS or Managed)
- **API Token** with permissions:
  - `DataExport`
  - `ReadConfig`
  - `WriteConfig`
  - `InstallerDownload`
  - `entities.read`
  - `settings.read`
  - `settings.write`
  - `bizevents.ingest` (for Business Events)
- **PaaS Token** (Data Ingest Token) for OneAgent installation

## Architecture Overview

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│ Tier 1  │────▶│ Tier 2  │────▶│ Tier 3  │     │ Tier 4  │────▶│ Tier 5  │
│ Node.js │     │  Java   │     │    C    │     │ Python  │     │  .NET   │
│  (K8s)  │     │  (K8s)  │     │  (EC2)  │     │  (K8s)  │     │  (EC2)  │
└─────────┘     └─────────┘     └────┬────┘     └────┬────┘     └────┬────┘
                                     │               │               │
                                     └───────────────┴───────────────┘
                                              ▼
                                        ┌──────────┐
                                        │   RDS    │
                                        │PostgreSQL│
                                        └──────────┘
```

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
aws_region = "us-east-1"
project_name = "dynatrace-bo-demo"

# Database
db_username = "loanadmin"
db_password = "YourSecurePassword123!"
db_name = "loandb"

# Dynatrace
dt_env_url = "https://abc12345.live.dynatrace.com"
dt_paas_token = "dt0c01.YOUR_PAAS_TOKEN"
dt_api_token = "dt0c01.YOUR_API_TOKEN"

# Application
base_rate = "0.05"
approval_threshold = "60"
rejection_threshold = "40"

# Authorization
unauthorized_regions = "Sanctioned,Restricted"
unauthorized_channels = "External,Public"
```

### 1.3 Initialize and Deploy
```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy infrastructure (takes ~15-20 minutes)
terraform apply
```

### 1.4 Save Outputs
```bash
# Get important outputs
terraform output -raw kubeconfig_command > /tmp/kubeconfig.sh
terraform output tier3_private_ip
terraform output tier5_private_ip
terraform output rds_endpoint

# Configure kubectl
bash /tmp/kubeconfig.sh
kubectl get nodes  # Verify cluster access
```

## Step 2: Build and Push Docker Images

### 2.1 Create ECR Repositories
```bash
aws ecr create-repository --repository-name tier1-loan-submission --region us-east-1
aws ecr create-repository --repository-name tier2-credit-analysis --region us-east-1
aws ecr create-repository --repository-name tier4-decision-engine --region us-east-1
```

### 2.2 Login to ECR
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
```

### 2.3 Build and Push Images
```bash
# Set your ECR registry URL
export ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Tier 1
cd ../../tier1-node
docker build -t $ECR_REGISTRY/tier1-loan-submission:latest .
docker push $ECR_REGISTRY/tier1-loan-submission:latest

# Tier 2
cd ../tier2-java
docker build -t $ECR_REGISTRY/tier2-credit-analysis:latest .
docker push $ECR_REGISTRY/tier2-credit-analysis:latest

# Tier 4
cd ../tier4-saas-sim
docker build -t $ECR_REGISTRY/tier4-decision-engine:latest .
docker push $ECR_REGISTRY/tier4-decision-engine:latest
```

## Step 3: Deploy EC2 Applications

### 3.1 Tier 3 (C Legacy Application)

SSH into Tier 3 EC2 instance:
```bash
TIER3_IP=$(terraform output -raw tier3_private_ip)
ssh -i ~/.ssh/your-key.pem ec2-user@$TIER3_IP
```

The application is already installed via userdata. Verify:
```bash
sudo systemctl status loan-risk-engine
sudo journalctl -u loan-risk-engine -f
```

### 3.2 Tier 5 (.NET Application)

SSH into Tier 5 EC2 instance:
```bash
TIER5_IP=$(terraform output -raw tier5_private_ip)
ssh -i ~/.ssh/your-key.pem ec2-user@$TIER5_IP
```

Copy and deploy the application:
```bash
# On your local machine, build the .NET app
cd tier5-dotnet
dotnet publish -c Release -o ./publish

# Copy to EC2
scp -i ~/.ssh/your-key.pem -r ./publish/* ec2-user@$TIER5_IP:/opt/loan-finalizer/

# On EC2, start the service
sudo systemctl daemon-reload
sudo systemctl enable loan-finalizer
sudo systemctl start loan-finalizer
sudo systemctl status loan-finalizer
```

## Step 4: Install Dynatrace Operator

### 4.1 Add Helm Repository
```bash
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm repo update
```

### 4.2 Install Operator
```bash
helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --create-namespace \
  --set installCRD=true
```

### 4.3 Configure DynaKube
```bash
cd k8s/dynatrace-operator

# Edit 01-secret.yaml with your tokens
kubectl apply -f 01-secret.yaml

# Edit 02-dynakube.yaml with your environment URL
kubectl apply -f 02-dynakube.yaml
```

### 4.4 Verify Installation
```bash
kubectl get pods -n dynatrace
kubectl get dynakube -n dynatrace
```

Wait for OneAgent DaemonSet to be running on all nodes.

## Step 5: Deploy Kubernetes Applications

### 5.1 Create Namespace
```bash
kubectl apply -f k8s/namespace/loan-app-namespace.yaml
```

### 5.2 Update Configuration

Get EC2 private IPs from Terraform:
```bash
TIER3_IP=$(cd infra/terraform && terraform output -raw tier3_private_ip)
TIER5_IP=$(cd infra/terraform && terraform output -raw tier5_private_ip)
```

Update ConfigMaps:
```bash
# Tier 2 - Update TIER3_URL
sed -i "s/TIER3_EC2_PRIVATE_IP/$TIER3_IP/g" k8s/tier2/01-configmap.yaml

# Tier 4 - Update TIER5_URL
sed -i "s/TIER5_EC2_PRIVATE_IP/$TIER5_IP/g" k8s/tier4/01-configmap.yaml
```

Update image references in deployments:
```bash
export ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Update Tier 1
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" k8s/tier1/03-deployment.yaml

# Update Tier 2
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" k8s/tier2/02-deployment.yaml

# Update Tier 4 secret and deployment
sed -i "s|YOUR_ENVIRONMENT_ID|abc12345|g" k8s/tier4/02-secret.yaml
sed -i "s|YOUR_API_TOKEN_HERE|your-actual-token|g" k8s/tier4/02-secret.yaml
sed -i "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" k8s/tier4/03-deployment.yaml
```

### 5.3 Deploy All Tiers
```bash
# Tier 1
kubectl apply -f k8s/tier1/

# Tier 2
kubectl apply -f k8s/tier2/

# Tier 4
kubectl apply -f k8s/tier4/

# Verify deployments
kubectl get pods -n loan-app
kubectl get svc -n loan-app
```

### 5.4 Get Load Balancer URL
```bash
kubectl get svc tier1-service -n loan-app

# Wait for EXTERNAL-IP (may take 2-3 minutes)
export TIER1_URL=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://$TIER1_URL"
```

## Step 6: Verify End-to-End Flow

### 6.1 Test Request
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

### 6.2 Check Logs

**Tier 1 (Node.js):**
```bash
kubectl logs -n loan-app -l app=tier1 --tail=50
```

**Tier 2 (Java):**
```bash
kubectl logs -n loan-app -l app=tier2 --tail=50
```

**Tier 3 (C):**
```bash
ssh ec2-user@$TIER3_IP
sudo tail -f /var/log/loan-risk-engine/app.log
```

**Tier 4 (Python):**
```bash
kubectl logs -n loan-app -l app=tier4 --tail=50
```

**Tier 5 (.NET):**
```bash
ssh ec2-user@$TIER5_IP
sudo journalctl -u loan-finalizer -f
```

## Step 7: Verify in Dynatrace

### 7.1 Check Services
1. Open Dynatrace UI
2. Go to **Services**
3. You should see:
   - loan-submission (Node.js)
   - credit-analysis (Java)
   - loan-finalizer (.NET)

### 7.2 Check Distributed Traces
1. Go to **Distributed traces**
2. Filter by service: loan-submission
3. You should see complete traces spanning:
   - Tier 1 → Tier 2 → Tier 3 → Tier 4 → Tier 5 → Database

### 7.3 Check Business Events
1. Go to **Business Analytics** → **Business Events**
2. You should see events with:
   - Event Type: `loan.decision`
   - Attributes: decision, finalScore, approvedAmount, costCenter, etc.

### 7.4 Check Infrastructure
1. Go to **Infrastructure** → **Hosts**
2. Verify Tier 3 EC2 (infra-only monitoring)
3. Verify Tier 5 EC2 (full-stack monitoring)
4. Check EKS nodes

## Troubleshooting

### Pods Not Starting
```bash
kubectl describe pod <pod-name> -n loan-app
kubectl logs <pod-name> -n loan-app
```

### OneAgent Issues
```bash
kubectl get pods -n dynatrace
kubectl logs -n dynatrace -l app.kubernetes.io/name=dynatrace-operator
```

### EC2 Connectivity
```bash
# Test from EKS node to EC2
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- sh
curl http://<EC2_PRIVATE_IP>:8000/health
```

### Database Connection
```bash
# Check from Tier 5 EC2
psql -h <RDS_ENDPOINT> -U loanadmin -d loandb
\dt  # List tables
SELECT * FROM loan_applications LIMIT 10;
```

## Cleanup

To destroy all resources:
```bash
# Delete Kubernetes resources
kubectl delete namespace loan-app
helm uninstall dynatrace-operator -n dynatrace

# Destroy infrastructure
cd infra/terraform
terraform destroy
```

## Next Steps

- Review [DEMO.md](DEMO.md) for demonstration scenarios
- See [COST_ALLOCATION.md](COST_ALLOCATION.md) for cost allocation setup
- Load test the application
- Explore Dynatrace dashboards
