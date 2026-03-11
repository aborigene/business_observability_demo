# Deployment Scripts

This directory contains automation scripts for deploying the Dynatrace Business Observability Demo.

## Scripts Overview

### build-images.sh
Builds all Docker images for Kubernetes services (Tier 1, 2, 4).

**Usage:**
```bash
./scripts/build-images.sh
```

**Environment Variables:**
- `ECR_REGISTRY` (optional): ECR registry URL, auto-detected if not set

**Output:**
- Docker images tagged with `latest` and timestamp
- Summary of built images

---

### push-to-ecr.sh
Pushes Docker images to AWS ECR.

**Usage:**
```bash
./scripts/push-to-ecr.sh
```

**Prerequisites:**
- AWS CLI configured
- Docker images built (run `build-images.sh` first)

**Actions:**
- Logs into AWS ECR
- Creates repositories if they don't exist
- Pushes images with both `latest` and timestamped tags

---

### deploy-k8s.sh
Deploys all Kubernetes resources to EKS cluster.

**Usage:**
```bash
./scripts/deploy-k8s.sh
```

**Prerequisites:**
- kubectl configured with EKS cluster access
- Images pushed to ECR
- EC2 private IPs updated in ConfigMaps

**Actions:**
- Creates `loan-app` namespace
- Deploys Tier 1, 2, and 4 with ConfigMaps, Secrets, Deployments, HPAs
- Waits for deployments to be ready
- Displays Load Balancer URL

---

### deploy-all.sh
Complete end-to-end deployment automation.

**Usage:**
```bash
./scripts/deploy-all.sh
```

**Prerequisites:**
- All tools installed (aws, terraform, kubectl, helm, docker)
- `terraform.tfvars` configured

**Steps:**
1. Check prerequisites
2. Deploy infrastructure (Terraform)
3. Build and push Docker images
4. Deploy Dynatrace Operator (with manual secret/DynaKube config)
5. Deploy Kubernetes applications
6. Deploy EC2 applications (manual Tier 5 step)
7. Verify deployment

**Duration:** ~25-30 minutes for complete deployment

---

### cleanup.sh
Removes all deployed resources.

**Usage:**
```bash
./scripts/cleanup.sh
```

**Actions:**
- Deletes Kubernetes namespace `loan-app`
- Uninstalls Dynatrace Operator
- Destroys Terraform infrastructure (VPC, EKS, EC2, RDS)
- Optionally deletes ECR repositories

**Warning:** This is destructive and cannot be undone!

---

## Deployment Workflow

### Option 1: Automated Deployment
```bash
# Complete automated deployment
./scripts/deploy-all.sh
```

### Option 2: Step-by-Step Deployment
```bash
# 1. Deploy infrastructure
cd infra/terraform
terraform init
terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name <cluster-name>

# 3. Build images
./scripts/build-images.sh

# 4. Push to ECR
./scripts/push-to-ecr.sh

# 5. Install Dynatrace Operator
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace --create-namespace --set installCRD=true

# Edit and apply DynaKube
kubectl apply -f k8s/dynatrace-operator/

# 6. Deploy applications
./scripts/deploy-k8s.sh

# 7. Deploy Tier 5 to EC2 manually
cd tier5-dotnet
dotnet publish -c Release -o ./publish
scp -r ./publish/* ec2-user@<tier5-ip>:/opt/loan-finalizer/
ssh ec2-user@<tier5-ip> "sudo systemctl start loan-finalizer"
```

## Configuration Required

Before running deployment scripts:

1. **Terraform Variables** (`infra/terraform/terraform.tfvars`):
   - AWS credentials and region
   - Dynatrace tokens
   - Database credentials
   - Application configuration

2. **Kubernetes Secrets** (`k8s/dynatrace-operator/01-secret.yaml`):
   - Dynatrace API token
   - Dynatrace PaaS token

3. **Kubernetes ConfigMaps**:
   - Update EC2 private IPs in `k8s/tier2/01-configmap.yaml`
   - Update EC2 private IPs in `k8s/tier4/01-configmap.yaml`

4. **Tier 4 Secret** (`k8s/tier4/02-secret.yaml`):
   - Dynatrace environment URL
   - Dynatrace API token (with bizevents.ingest)

## Troubleshooting

### Images fail to build
- Check Docker daemon is running
- Verify Dockerfile exists in each tier directory
- Check for syntax errors in application code

### Cannot push to ECR
- Verify AWS CLI credentials: `aws sts get-caller-identity`
- Check ECR login: `aws ecr get-login-password`
- Ensure IAM permissions for ECR

### Pods not starting
```bash
# Check pod status
kubectl get pods -n loan-app

# View pod events
kubectl describe pod <pod-name> -n loan-app

# Check logs
kubectl logs <pod-name> -n loan-app
```

### LoadBalancer IP not assigned
```bash
# Wait up to 5 minutes for AWS to provision
kubectl get svc tier1-service -n loan-app --watch

# Check ELB in AWS Console
aws elbv2 describe-load-balancers
```

### EC2 applications not working
```bash
# Tier 3: Check service status
ssh ec2-user@<tier3-ip> "sudo systemctl status loan-risk-engine"

# View logs
ssh ec2-user@<tier3-ip> "sudo journalctl -u loan-risk-engine -f"

# Tier 5: Check service status  
ssh ec2-user@<tier5-ip> "sudo systemctl status loan-finalizer"

# View logs
ssh ec2-user@<tier5-ip> "sudo journalctl -u loan-finalizer -f"
```

## Common Issues

### Issue: kubectl cannot connect to cluster
**Solution:**
```bash
aws eks update-kubeconfig --name <cluster-name> --region us-east-1
```

### Issue: Terraform state locked
**Solution:**
```bash
cd infra/terraform
terraform force-unlock <lock-id>
```

### Issue: OneAgent not injecting
**Solution:**
1. Check DynaKube status: `kubectl get dynakube -n dynatrace`
2. Review operator logs: `kubectl logs -n dynatrace -l app.kubernetes.io/name=dynatrace-operator`
3. Verify secret is correct: `kubectl get secret dynakube-secret -n dynatrace -o yaml`

## Environment Variables Reference

Scripts use these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `ECR_REGISTRY` | AWS ECR registry URL | Auto-detected from AWS account |
| `AWS_REGION` | AWS region | `us-east-1` |
| `TIER3_PRIVATE_IP` | Tier 3 EC2 private IP | From Terraform output |
| `TIER5_PRIVATE_IP` | Tier 5 EC2 private IP | From Terraform output |
| `TIER1_URL` | Tier 1 LoadBalancer URL | From kubectl get svc |

## Testing After Deployment

```bash
# Get application URL
export TIER1_URL=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test approved scenario
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-approved.json

# Test rejected scenario
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-rejected.json

# Test unauthorized scenario
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-unauthorized.json
```

## Cleanup

To remove all resources:
```bash
./scripts/cleanup.sh
```

**Note:** This will delete everything including data in RDS!

## Next Steps

After successful deployment:
1. Open Dynatrace UI and verify services are monitored
2. Check distributed traces
3. View Business Events in Business Analytics
4. Review [DEMO.md](../docs/DEMO.md) for demonstration scenarios
5. Set up cost allocation dashboards per [COST_ALLOCATION.md](../docs/COST_ALLOCATION.md)
