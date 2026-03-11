#!/bin/bash
# Complete deployment script - orchestrates all deployment steps

set -e

echo "=========================================="
echo "Complete Deployment Automation"
echo "Dynatrace Business Observability Demo"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check prerequisites
check_prerequisites() {
    echo ""
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=0
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not found${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ AWS CLI${NC}"
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}✗ Terraform not found${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Terraform${NC}"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl not found${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ kubectl${NC}"
    fi
    
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}✗ Helm not found${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Helm${NC}"
    fi
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker not found${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Docker${NC}"
    fi
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Missing prerequisites. Please install required tools.${NC}"
        exit 1
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "STEP 1: Deploying Infrastructure"
    echo "==========================================${NC}"
    
    cd "$PROJECT_ROOT/infra/terraform"
    
    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}Error: terraform.tfvars not found${NC}"
        echo "Create it from terraform.tfvars.example and fill in your values"
        exit 1
    fi
    
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
    
    echo -e "${YELLOW}Planning infrastructure...${NC}"
    terraform plan -out=tfplan
    
    read -p "Apply this plan? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Infrastructure deployment cancelled."
        exit 0
    fi
    
    echo -e "${YELLOW}Applying infrastructure (this may take 15-20 minutes)...${NC}"
    terraform apply tfplan
    
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
    
    # Configure kubectl
    echo -e "${YELLOW}Configuring kubectl...${NC}"
    terraform output -raw kubeconfig_command | bash
    
    # Export outputs
    export TIER3_PRIVATE_IP=$(terraform output -raw tier3_private_ip)
    export TIER5_PRIVATE_IP=$(terraform output -raw tier5_private_ip)
    export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
    
    echo -e "${GREEN}✓ kubectl configured${NC}"
}

# Build and push images
build_and_push_images() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "STEP 2: Building and Pushing Docker Images"
    echo "==========================================${NC}"
    
    cd "$PROJECT_ROOT"
    
    # Set ECR registry
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=${AWS_REGION:-us-east-1}
    export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    # Build images
    bash "$SCRIPT_DIR/build-images.sh"
    
    # Push images
    bash "$SCRIPT_DIR/push-to-ecr.sh"
    
    echo -e "${GREEN}✓ Images built and pushed${NC}"
}

# Deploy Dynatrace Operator
deploy_dynatrace() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "STEP 3: Deploying Dynatrace Operator"
    echo "==========================================${NC}"
    
    echo -e "${YELLOW}Adding Dynatrace Helm repository...${NC}"
    helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
    helm repo update
    
    echo -e "${YELLOW}Installing Dynatrace Operator...${NC}"
    helm install dynatrace-operator dynatrace/dynatrace-operator \
        --namespace dynatrace \
        --create-namespace \
        --set installCRD=true
    
    echo -e "${YELLOW}Please update the Dynatrace secrets and DynaKube:${NC}"
    echo "  1. Edit: k8s/dynatrace-operator/01-secret.yaml"
    echo "  2. Edit: k8s/dynatrace-operator/02-dynakube.yaml"
    echo "  3. Apply: kubectl apply -f k8s/dynatrace-operator/"
    echo ""
    read -p "Press Enter when ready to continue..."
    
    echo -e "${GREEN}✓ Dynatrace Operator deployed${NC}"
}

# Deploy applications
deploy_applications() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "STEP 4: Deploying Applications"
    echo "==========================================${NC}"
    
    bash "$SCRIPT_DIR/deploy-k8s.sh"
    
    echo -e "${GREEN}✓ Applications deployed${NC}"
}

# Deploy EC2 applications
deploy_ec2_apps() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "STEP 5: Deploying EC2 Applications"
    echo "==========================================${NC}"
    
    echo -e "${YELLOW}Tier 3 (C) is already deployed via userdata${NC}"
    echo "Verify: ssh ec2-user@$TIER3_PRIVATE_IP 'sudo systemctl status loan-risk-engine'"
    
    echo ""
    echo -e "${YELLOW}Tier 5 (.NET) requires manual deployment:${NC}"
    echo "1. Build: cd tier5-dotnet && dotnet publish -c Release -o ./publish"
    echo "2. Copy: scp -r ./publish/* ec2-user@$TIER5_PRIVATE_IP:/opt/loan-finalizer/"
    echo "3. Start: ssh ec2-user@$TIER5_PRIVATE_IP 'sudo systemctl start loan-finalizer'"
    echo ""
    read -p "Complete Tier 5 deployment and press Enter to continue..."
    
    echo -e "${GREEN}✓ EC2 applications deployed${NC}"
}

# Verify deployment
verify_deployment() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "STEP 6: Verifying Deployment"
    echo "==========================================${NC}"
    
    echo -e "${YELLOW}Checking pod status...${NC}"
    kubectl get pods -n loan-app
    
    echo ""
    echo -e "${YELLOW}Checking services...${NC}"
    kubectl get svc -n loan-app
    
    echo ""
    echo -e "${YELLOW}Getting application URL...${NC}"
    TIER1_URL=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ ! -z "$TIER1_URL" ]; then
        echo -e "${GREEN}Application URL: http://$TIER1_URL${NC}"
        
        echo ""
        echo -e "${YELLOW}Testing application...${NC}"
        sleep 10  # Wait for LB to be fully ready
        
        curl -X POST "http://$TIER1_URL/api/loan/submit" \
            -H "Content-Type: application/json" \
            -d @"$PROJECT_ROOT/examples/loan-request-approved.json" \
            -w "\nHTTP Status: %{http_code}\n"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Application is responding${NC}"
        else
            echo -e "${YELLOW}⚠ Application may still be starting up${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ LoadBalancer IP not yet assigned${NC}"
    fi
}

# Main execution
main() {
    check_prerequisites
    
    echo ""
    echo -e "${BLUE}This script will:${NC}"
    echo "1. Deploy AWS infrastructure (VPC, EKS, EC2, RDS)"
    echo "2. Build and push Docker images to ECR"
    echo "3. Deploy Dynatrace Operator"
    echo "4. Deploy Kubernetes applications"
    echo "5. Deploy EC2 applications"
    echo "6. Verify deployment"
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    deploy_infrastructure
    build_and_push_images
    deploy_dynatrace
    deploy_applications
    deploy_ec2_apps
    verify_deployment
    
    echo ""
    echo -e "${GREEN}=========================================="
    echo "DEPLOYMENT COMPLETE!"
    echo "==========================================${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Open Dynatrace UI and verify monitoring"
    echo "2. Check distributed traces"
    echo "3. View Business Events"
    echo "4. Review docs/DEMO.md for demonstration scenarios"
    echo ""
    echo -e "${BLUE}Application URL:${NC}"
    echo "  http://$TIER1_URL"
    echo ""
    echo -e "${BLUE}Test command:${NC}"
    echo "  curl -X POST http://$TIER1_URL/api/loan/submit \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d @examples/loan-request-approved.json"
}

# Run main
main
