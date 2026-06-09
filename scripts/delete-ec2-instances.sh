#!/bin/bash
# Delete the Tier 3 and Tier 5 EC2 instances created by the previous deployment.
# Safe to run multiple times — exits cleanly if instances are already gone.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION=${AWS_REGION:-us-east-1}
PROJECT_NAME=${PROJECT_NAME:-dynatrace-busines-o11y-demo}
ENVIRONMENT=${ENVIRONMENT:-demo}

echo "=========================================="
echo "Deleting Tier 3 & Tier 5 EC2 Instances"
echo "Region  : $AWS_REGION"
echo "Project : $PROJECT_NAME"
echo "Env     : $ENVIRONMENT"
echo "=========================================="

find_instance() {
    local name_suffix=$1
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters \
            "Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-${name_suffix}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null
}

terminate_instance() {
    local name_suffix=$1
    local display_name=$2

    echo ""
    echo -e "${YELLOW}Looking for: ${display_name}...${NC}"
    INSTANCE_ID=$(find_instance "$name_suffix")

    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${GREEN}✓ No running instance found for ${display_name} — already deleted or never created.${NC}"
        return 0
    fi

    echo -e "${YELLOW}  Found: $INSTANCE_ID — terminating...${NC}"
    aws ec2 terminate-instances \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --output text > /dev/null

    echo -e "${GREEN}✓ Termination initiated for $INSTANCE_ID (${display_name})${NC}"
}

terminate_instance "tier3-risk-analysis"  "Tier 3 (C Legacy - Risk Analysis)"
terminate_instance "tier5-loan-finalizer" "Tier 5 (.NET - Loan Finalizer)"

echo ""
echo -e "${GREEN}=========================================="
echo "Done. Instances are being terminated."
echo "==========================================${NC}"
echo ""
echo "Note: Termination takes ~1-2 minutes. Verify with:"
echo "  aws ec2 describe-instances \\"
echo "    --region $AWS_REGION \\"
echo "    --filters 'Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-tier*' \\"
echo "    --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==\`Name\`].Value|[0]]' \\"
echo "    --output table"
