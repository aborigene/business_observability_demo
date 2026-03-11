#!/bin/bash
# Build all Docker images for the loan application

set -e

echo "=========================================="
echo "Building Docker Images"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if ECR registry is set
if [ -z "$ECR_REGISTRY" ]; then
    echo -e "${YELLOW}Warning: ECR_REGISTRY not set${NC}"
    echo "Getting AWS account ID..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=${AWS_REGION:-us-east-1}
    export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    echo -e "${GREEN}Using ECR registry: $ECR_REGISTRY${NC}"
fi

# Function to build image
build_image() {
    local service=$1
    local dir=$2
    local image_name=$3
    
    echo ""
    echo -e "${YELLOW}Building $service...${NC}"
    cd "$PROJECT_ROOT/$dir"
    
    if [ ! -f "Dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found in $dir${NC}"
        return 1
    fi
    
    docker build -t "$ECR_REGISTRY/$image_name:latest" .
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully built $service${NC}"
        # Also tag with timestamp
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        docker tag "$ECR_REGISTRY/$image_name:latest" "$ECR_REGISTRY/$image_name:$TIMESTAMP"
        echo -e "${GREEN}  Tagged as: $image_name:$TIMESTAMP${NC}"
    else
        echo -e "${RED}✗ Failed to build $service${NC}"
        return 1
    fi
}

# Build all images
echo ""
build_image "Tier 1 (Node.js)" "tier1-node" "tier1-loan-submission"
build_image "Tier 2 (Java)" "tier2-java" "tier2-credit-analysis"
build_image "Tier 4 (Python)" "tier4-saas-sim" "tier4-decision-engine"

echo ""
echo -e "${GREEN}=========================================="
echo "All images built successfully!"
echo "==========================================${NC}"
echo ""
echo "To push images to ECR, run:"
echo "  ./scripts/push-to-ecr.sh"
echo ""
echo "Built images:"
docker images | grep -E "(tier1-loan-submission|tier2-credit-analysis|tier4-decision-engine)"
