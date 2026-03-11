#!/bin/bash
# Push Docker images to AWS ECR

set -e

echo "=========================================="
echo "Pushing Images to ECR"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check ECR_REGISTRY
if [ -z "$ECR_REGISTRY" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=${AWS_REGION:-us-east-1}
    export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
fi

echo -e "${GREEN}ECR Registry: $ECR_REGISTRY${NC}"

# Login to ECR
echo ""
echo -e "${YELLOW}Logging into ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION:-us-east-1} | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to login to ECR${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Logged in to ECR${NC}"

# Function to create repository if it doesn't exist
create_repo_if_not_exists() {
    local repo_name=$1
    
    echo -e "${YELLOW}Checking repository: $repo_name${NC}"
    
    aws ecr describe-repositories --repository-names $repo_name --region ${AWS_REGION:-us-east-1} > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Creating repository: $repo_name${NC}"
        aws ecr create-repository \
            --repository-name $repo_name \
            --region ${AWS_REGION:-us-east-1} \
            --image-scanning-configuration scanOnPush=true
        echo -e "${GREEN}✓ Repository created${NC}"
    else
        echo -e "${GREEN}✓ Repository exists${NC}"
    fi
}

# Function to push image
push_image() {
    local image_name=$1
    
    echo ""
    echo -e "${YELLOW}Pushing $image_name...${NC}"
    
    docker push "$ECR_REGISTRY/$image_name:latest"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully pushed $image_name:latest${NC}"
        
        # Also push timestamped tag if it exists
        TIMESTAMP_TAG=$(docker images "$ECR_REGISTRY/$image_name" --format "{{.Tag}}" | grep -v latest | head -1)
        if [ ! -z "$TIMESTAMP_TAG" ]; then
            docker push "$ECR_REGISTRY/$image_name:$TIMESTAMP_TAG"
            echo -e "${GREEN}✓ Successfully pushed $image_name:$TIMESTAMP_TAG${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to push $image_name${NC}"
        return 1
    fi
}

# Create repositories
echo ""
echo -e "${YELLOW}Ensuring ECR repositories exist...${NC}"
create_repo_if_not_exists "tier1-loan-submission"
create_repo_if_not_exists "tier2-credit-analysis"
create_repo_if_not_exists "tier4-decision-engine"

# Push images
echo ""
echo -e "${YELLOW}Pushing images...${NC}"
push_image "tier1-loan-submission"
push_image "tier2-credit-analysis"
push_image "tier4-decision-engine"

echo ""
echo -e "${GREEN}=========================================="
echo "All images pushed successfully!"
echo "==========================================${NC}"
echo ""
echo "Image URIs:"
echo "  Tier 1: $ECR_REGISTRY/tier1-loan-submission:latest"
echo "  Tier 2: $ECR_REGISTRY/tier2-credit-analysis:latest"
echo "  Tier 4: $ECR_REGISTRY/tier4-decision-engine:latest"
echo ""
echo "Next steps:"
echo "  1. Update Kubernetes manifests with these image URIs"
echo "  2. Run: ./scripts/deploy-k8s.sh"
