#!/bin/bash
# VPC Validation Script for Dynatrace Business Observability Demo
# This script validates that an existing VPC meets the requirements for deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
CHECKS_PASSED=0

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    echo "Install it from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq is not installed${NC}"
    echo "Install it with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Usage information
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <vpc-id> [region]"
    echo ""
    echo "Example:"
    echo "  $0 vpc-0123456789abcdef us-east-1"
    echo ""
    echo "This script validates that your VPC meets the requirements:"
    echo "  - DNS Support enabled"
    echo "  - DNS Hostnames enabled"
    echo "  - At least 2 public subnets in different AZs"
    echo "  - At least 2 private subnets in different AZs"
    echo "  - Internet Gateway attached"
    echo "  - NAT Gateway(s) for private subnet internet access"
    echo "  - Proper subnet tags for EKS"
    exit 1
fi

VPC_ID=$1
AWS_REGION=${2:-us-east-1}

print_header "Validating VPC: $VPC_ID in region: $AWS_REGION"

# Validate VPC exists and get details
print_info "Checking if VPC exists..."
VPC_INFO=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" 2>&1) || {
    print_error "VPC $VPC_ID not found in region $AWS_REGION"
    exit 1
}

print_success "VPC found: $VPC_ID"

# Extract VPC details
VPC_CIDR=$(echo "$VPC_INFO" | jq -r '.Vpcs[0].CidrBlock')
DNS_SUPPORT=$(echo "$VPC_INFO" | jq -r '.Vpcs[0].EnableDnsSupport')
DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames --region "$AWS_REGION" | jq -r '.EnableDnsHostnames.Value')

print_info "VPC CIDR: $VPC_CIDR"

# Check DNS Support
print_header "DNS Configuration"
if [ "$DNS_SUPPORT" == "true" ]; then
    print_success "DNS Support is enabled"
else
    print_error "DNS Support is NOT enabled (required for EKS)"
    echo "  Fix with: aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support"
fi

if [ "$DNS_HOSTNAMES" == "true" ]; then
    print_success "DNS Hostnames is enabled"
else
    print_error "DNS Hostnames is NOT enabled (required for EKS)"
    echo "  Fix with: aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames"
fi

# Check Internet Gateway
print_header "Internet Gateway"
IGW_INFO=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region "$AWS_REGION")
IGW_COUNT=$(echo "$IGW_INFO" | jq '.InternetGateways | length')

if [ "$IGW_COUNT" -gt 0 ]; then
    IGW_ID=$(echo "$IGW_INFO" | jq -r '.InternetGateways[0].InternetGatewayId')
    print_success "Internet Gateway found: $IGW_ID"
else
    print_error "No Internet Gateway attached to VPC (required for public subnet internet access)"
    echo "  Create and attach one with:"
    echo "  aws ec2 create-internet-gateway --region $AWS_REGION"
    echo "  aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id <igw-id>"
fi

# Check Subnets
print_header "Subnets"
SUBNETS_INFO=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$AWS_REGION")
TOTAL_SUBNETS=$(echo "$SUBNETS_INFO" | jq '.Subnets | length')

if [ "$TOTAL_SUBNETS" -lt 4 ]; then
    print_warning "Found only $TOTAL_SUBNETS subnets (recommended: at least 4 - 2 public, 2 private)"
else
    print_success "Found $TOTAL_SUBNETS subnets"
fi

# Analyze subnet types
PUBLIC_SUBNETS=()
PRIVATE_SUBNETS=()
PUBLIC_AZS=()
PRIVATE_AZS=()

while IFS= read -r subnet_id; do
    SUBNET_INFO=$(echo "$SUBNETS_INFO" | jq -r ".Subnets[] | select(.SubnetId==\"$subnet_id\")")
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet_id" --region "$AWS_REGION" | jq -r '.RouteTables[0].RouteTableId // empty')
    
    # If no explicit association, get the main route table
    if [ -z "$ROUTE_TABLE_ID" ]; then
        ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" --region "$AWS_REGION" | jq -r '.RouteTables[0].RouteTableId')
    fi
    
    ROUTES=$(aws ec2 describe-route-tables --route-table-ids "$ROUTE_TABLE_ID" --region "$AWS_REGION" | jq -r '.RouteTables[0].Routes')
    HAS_IGW=$(echo "$ROUTES" | jq 'any(.GatewayId; . != null and startswith("igw-"))')
    
    SUBNET_AZ=$(echo "$SUBNET_INFO" | jq -r '.AvailabilityZone')
    
    if [ "$HAS_IGW" == "true" ]; then
        PUBLIC_SUBNETS+=("$subnet_id")
        PUBLIC_AZS+=("$SUBNET_AZ")
    else
        PRIVATE_SUBNETS+=("$subnet_id")
        PRIVATE_AZS+=("$SUBNET_AZ")
    fi
done < <(echo "$SUBNETS_INFO" | jq -r '.Subnets[].SubnetId')

# Validate public subnets
print_info "\nPublic Subnets (${#PUBLIC_SUBNETS[@]}):"
if [ "${#PUBLIC_SUBNETS[@]}" -ge 2 ]; then
    UNIQUE_PUBLIC_AZS=$(printf '%s\n' "${PUBLIC_AZS[@]}" | sort -u | wc -l)
    if [ "$UNIQUE_PUBLIC_AZS" -ge 2 ]; then
        print_success "At least 2 public subnets in different AZs"
        for i in "${!PUBLIC_SUBNETS[@]}"; do
            echo "  - ${PUBLIC_SUBNETS[$i]} (${PUBLIC_AZS[$i]})"
        done
    else
        print_error "Public subnets are not in at least 2 different AZs (required for EKS Load Balancers)"
    fi
else
    print_error "Need at least 2 public subnets (found: ${#PUBLIC_SUBNETS[@]})"
fi

# Validate private subnets
print_info "\nPrivate Subnets (${#PRIVATE_SUBNETS[@]}):"
if [ "${#PRIVATE_SUBNETS[@]}" -ge 2 ]; then
    UNIQUE_PRIVATE_AZS=$(printf '%s\n' "${PRIVATE_AZS[@]}" | sort -u | wc -l)
    if [ "$UNIQUE_PRIVATE_AZS" -ge 2 ]; then
        print_success "At least 2 private subnets in different AZs"
        for i in "${!PRIVATE_SUBNETS[@]}"; do
            echo "  - ${PRIVATE_SUBNETS[$i]} (${PRIVATE_AZS[$i]})"
        done
    else
        print_error "Private subnets are not in at least 2 different AZs (required for EKS node groups)"
    fi
else
    print_error "Need at least 2 private subnets (found: ${#PRIVATE_SUBNETS[@]})"
fi

# Check NAT Gateways
print_header "NAT Gateways"
NAT_INFO=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --region "$AWS_REGION")
NAT_COUNT=$(echo "$NAT_INFO" | jq '.NatGateways | length')

if [ "$NAT_COUNT" -gt 0 ]; then
    print_success "Found $NAT_COUNT NAT Gateway(s)"
    echo "$NAT_INFO" | jq -r '.NatGateways[] | "  - \(.NatGatewayId) in \(.SubnetId)"'
else
    print_error "No NAT Gateways found (required for private subnet internet access)"
    echo "  EKS nodes in private subnets need NAT for pulling images and Dynatrace communication"
    echo "  Create NAT Gateway(s) in your public subnet(s)"
fi

# Check EKS subnet tags
print_header "EKS Subnet Tags"
PUBLIC_TAG_ISSUES=0
PRIVATE_TAG_ISSUES=0

for subnet_id in "${PUBLIC_SUBNETS[@]}"; do
    TAGS=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$subnet_id" "Name=key,Values=kubernetes.io/role/elb" --region "$AWS_REGION")
    TAG_VALUE=$(echo "$TAGS" | jq -r '.Tags[0].Value // empty')
    
    if [ "$TAG_VALUE" == "1" ]; then
        print_success "Public subnet $subnet_id has correct EKS tag"
    else
        print_warning "Public subnet $subnet_id missing tag: kubernetes.io/role/elb = 1"
        ((PUBLIC_TAG_ISSUES++))
    fi
done

for subnet_id in "${PRIVATE_SUBNETS[@]}"; do
    TAGS=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$subnet_id" "Name=key,Values=kubernetes.io/role/internal-elb" --region "$AWS_REGION")
    TAG_VALUE=$(echo "$TAGS" | jq -r '.Tags[0].Value // empty')
    
    if [ "$TAG_VALUE" == "1" ]; then
        print_success "Private subnet $subnet_id has correct EKS tag"
    else
        print_warning "Private subnet $subnet_id missing tag: kubernetes.io/role/internal-elb = 1"
        ((PRIVATE_TAG_ISSUES++))
    fi
done

if [ "$PUBLIC_TAG_ISSUES" -gt 0 ]; then
    echo -e "\n  ${YELLOW}To fix public subnet tags:${NC}"
    for subnet_id in "${PUBLIC_SUBNETS[@]}"; do
        echo "  aws ec2 create-tags --resources $subnet_id --tags Key=kubernetes.io/role/elb,Value=1 --region $AWS_REGION"
    done
fi

if [ "$PRIVATE_TAG_ISSUES" -gt 0 ]; then
    echo -e "\n  ${YELLOW}To fix private subnet tags:${NC}"
    for subnet_id in "${PRIVATE_SUBNETS[@]}"; do
        echo "  aws ec2 create-tags --resources $subnet_id --tags Key=kubernetes.io/role/internal-elb,Value=1 --region $AWS_REGION"
    done
fi

# Summary
print_header "Validation Summary"
echo "VPC ID: $VPC_ID"
echo "Region: $AWS_REGION"
echo "CIDR: $VPC_CIDR"
echo ""
echo -e "${GREEN}Checks Passed: $CHECKS_PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Errors: $ERRORS${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✓ VPC validation PASSED!${NC}"
    echo ""
    echo "Add these to your terraform.tfvars:"
    echo ""
    echo "use_existing_vpc = true"
    echo "existing_vpc_id = \"$VPC_ID\""
    echo "existing_public_subnet_ids = [$(printf '"%s",' "${PUBLIC_SUBNETS[@]}" | sed 's/,$//')]"
    echo "existing_private_subnet_ids = [$(printf '"%s",' "${PRIVATE_SUBNETS[@]}" | sed 's/,$//')]"
    echo ""
    
    if [ "$WARNINGS" -gt 0 ]; then
        echo -e "${YELLOW}Note: There are warnings that should be addressed for best results.${NC}"
        exit 0
    fi
    exit 0
else
    echo -e "${RED}✗ VPC validation FAILED!${NC}"
    echo "Please fix the errors above before proceeding with deployment."
    exit 1
fi
