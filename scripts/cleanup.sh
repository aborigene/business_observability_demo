#!/bin/bash
# Cleanup all resources

set -e

echo "=========================================="
echo "Cleanup Dynatrace BO Demo Resources"
echo "=========================================="

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${RED}WARNING: This will delete all resources including:${NC}"
echo "  - Kubernetes deployments and services"
echo "  - Dynatrace Operator"
echo "  - AWS infrastructure (VPC, EKS, EC2, RDS)"
echo "  - ECR repositories (optional)"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " -r
if [[ ! $REPLY == "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Delete Kubernetes resources
echo ""
echo -e "${YELLOW}Deleting Kubernetes resources...${NC}"
if command -v kubectl &> /dev/null; then
    kubectl delete namespace loan-app --ignore-not-found=true
    
    echo "Uninstalling Dynatrace Operator..."
    helm uninstall dynatrace-operator -n dynatrace --ignore-not-found || true
    kubectl delete namespace dynatrace --ignore-not-found=true
else
    echo "kubectl not found, skipping Kubernetes cleanup"
fi

# Destroy Terraform infrastructure
echo ""
echo -e "${YELLOW}Destroying AWS infrastructure...${NC}"
cd "$PROJECT_ROOT/infra/terraform"

if [ -f "terraform.tfstate" ]; then
    terraform destroy -auto-approve
else
    echo "No Terraform state found, skipping infrastructure cleanup"
fi

# Optional: Delete ECR repositories
echo ""
read -p "Delete ECR repositories? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deleting ECR repositories...${NC}"
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    for repo in tier1-loan-submission tier2-credit-analysis tier4-decision-engine; do
        aws ecr delete-repository \
            --repository-name $repo \
            --region $AWS_REGION \
            --force 2>/dev/null || echo "Repository $repo not found"
    done
fi

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
