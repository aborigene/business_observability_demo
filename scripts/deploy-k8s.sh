#!/bin/bash
# Deploy all Kubernetes resources

set -e

echo "=========================================="
echo "Deploying Loan Application to Kubernetes"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$PROJECT_ROOT/k8s"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Check cluster connectivity
echo -e "${YELLOW}Checking cluster connectivity...${NC}"
kubectl cluster-info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    echo "Run: aws eks update-kubeconfig --name <cluster-name>"
    exit 1
fi
echo -e "${GREEN}✓ Connected to cluster${NC}"

# Get ECR registry
if [ -z "$ECR_REGISTRY" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=${AWS_REGION:-us-east-1}
    export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
fi

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  ECR Registry: $ECR_REGISTRY"
echo "  Cluster: $(kubectl config current-context)"

# Confirmation prompt
read -p "Continue with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Function to update image in manifests
update_images() {
    echo ""
    echo -e "${YELLOW}Updating image references in manifests...${NC}"
    
    # Create temporary copies with updated images
    for tier in tier1 tier2 tier4; do
        if [ -f "$K8S_DIR/$tier/03-deployment.yaml" ] || [ -f "$K8S_DIR/$tier/02-deployment.yaml" ]; then
            deployment_file=$(ls $K8S_DIR/$tier/*deployment.yaml 2>/dev/null | head -1)
            sed "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" $deployment_file > ${deployment_file}.tmp
            mv ${deployment_file}.tmp $deployment_file
            echo -e "${GREEN}✓ Updated $tier deployment${NC}"
        fi
    done
}

# Update images
update_images

# Deploy namespace
echo ""
echo -e "${BLUE}=== Deploying Namespace ===${NC}"
kubectl apply -f "$K8S_DIR/namespace/loan-app-namespace.yaml"

# Deploy Tier 1
echo ""
echo -e "${BLUE}=== Deploying Tier 1 (Node.js) ===${NC}"
kubectl apply -f "$K8S_DIR/tier1/"

# Deploy Tier 2
echo ""
echo -e "${BLUE}=== Deploying Tier 2 (Java) ===${NC}"
kubectl apply -f "$K8S_DIR/tier2/"

# Deploy Tier 4
echo ""
echo -e "${BLUE}=== Deploying Tier 4 (Python) ===${NC}"
kubectl apply -f "$K8S_DIR/tier4/"

# Wait for deployments
echo ""
echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s \
    deployment/tier1-loan-submission -n loan-app
kubectl wait --for=condition=available --timeout=300s \
    deployment/tier2-credit-analysis -n loan-app
kubectl wait --for=condition=available --timeout=300s \
    deployment/tier4-decision-engine -n loan-app

# Get status
echo ""
echo -e "${GREEN}=========================================="
echo "Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${BLUE}Pod Status:${NC}"
kubectl get pods -n loan-app

echo ""
echo -e "${BLUE}Service Status:${NC}"
kubectl get svc -n loan-app

echo ""
echo -e "${YELLOW}Waiting for LoadBalancer IP...${NC}"
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ ! -z "$EXTERNAL_IP" ]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ ! -z "$EXTERNAL_IP" ]; then
    echo -e "${GREEN}Application URL: http://$EXTERNAL_IP${NC}"
    echo ""
    echo "Test the application:"
    echo "  curl -X POST http://$EXTERNAL_IP/api/loan/submit \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d @examples/loan-request-approved.json"
else
    echo -e "${YELLOW}LoadBalancer IP not yet assigned. Check with:${NC}"
    echo "  kubectl get svc tier1-service -n loan-app"
fi

echo ""
echo -e "${BLUE}View logs:${NC}"
echo "  kubectl logs -n loan-app -l app=tier1 --tail=50"
echo "  kubectl logs -n loan-app -l app=tier2 --tail=50"
echo "  kubectl logs -n loan-app -l app=tier4 --tail=50"

echo ""
echo -e "${BLUE}Monitor pods:${NC}"
echo "  watch kubectl get pods -n loan-app"
