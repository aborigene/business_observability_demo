# Existing VPC Support - Implementation Summary

## Overview

The Dynatrace Business Observability Demo now supports using an existing AWS VPC instead of creating a new one. This addresses AWS account VPC limits and allows integration with existing network infrastructure.

## What Was Changed

### 1. Terraform Configuration Updates

#### New Variables (`infra/terraform/variables.tf`)
- `use_existing_vpc` - Boolean flag to enable existing VPC mode (default: false)
- `existing_vpc_id` - ID of the existing VPC to use
- `existing_public_subnet_ids` - List of existing public subnet IDs
- `existing_private_subnet_ids` - List of existing private subnet IDs

#### New Data Sources (`infra/terraform/data.tf`)
- Data sources to fetch existing VPC details
- Data sources for existing subnets, Internet Gateway, NAT Gateways
- Validation logic that checks VPC requirements during Terraform apply
- Local values that abstract VPC source (new vs existing)

#### Updated Main Configuration (`infra/terraform/main.tf`)
- VPC module made conditional with `count` parameter
- All references to `module.vpc.*` replaced with `local.*` values
- Works seamlessly with both new and existing VPC modes

#### Updated Outputs (`infra/terraform/outputs.tf`)
- Added `vpc_source` output showing "created" or "existing"
- Added `public_subnet_ids` and `private_subnet_ids` outputs
- Now uses local values instead of direct module references

#### Updated Variables Example (`infra/terraform/terraform.tfvars.example`)
- Added examples for both deployment modes
- Documented VPC requirements
- Clear instructions for each option

### 2. VPC Validation Script

#### New Script (`scripts/validate-vpc.sh`)
A comprehensive validation script that checks:
- ✅ VPC existence and accessibility
- ✅ DNS Support enabled
- ✅ DNS Hostnames enabled
- ✅ At least 2 public subnets in different AZs
- ✅ At least 2 private subnets in different AZs
- ✅ Internet Gateway attached
- ✅ NAT Gateway(s) present
- ✅ Proper EKS subnet tags

**Features:**
- Colorized output for easy reading
- Detailed error messages with remediation commands
- Outputs ready-to-use Terraform configuration
- Returns appropriate exit codes

### 3. Documentation Updates

#### Updated Files:
- `README.md` - Added VPC deployment mode options in Quick Start
- `docs/SETUP.md` - Added comprehensive "Using an Existing VPC" section
- `scripts/README.md` - Documented the validate-vpc.sh script
- `infra/terraform/terraform.tfvars.example` - Added configuration examples

## How to Use

### Step 1: Validate Your Existing VPC

```bash
cd business_observability_demo
./scripts/validate-vpc.sh vpc-xxxxxxxxxxxxx us-east-1
```

The script will:
1. Check all VPC requirements
2. Display a detailed validation report
3. Output the exact configuration for terraform.tfvars
4. Exit with code 0 (pass) or 1 (fail)

### Step 2: Update Terraform Configuration

If validation passes, update your `infra/terraform/terraform.tfvars`:

```hcl
# Use existing VPC
use_existing_vpc = true
existing_vpc_id = "vpc-xxxxxxxxxxxxx"
existing_public_subnet_ids = ["subnet-pub1", "subnet-pub2"]
existing_private_subnet_ids = ["subnet-priv1", "subnet-priv2"]

# All other variables remain the same
aws_region = "us-east-1"
project_name = "dynatrace-bo-demo"
# ... rest of your configuration
```

### Step 3: Deploy Infrastructure

```bash
cd infra/terraform
terraform init
terraform plan  # Review what will be created (VPC module will be skipped)
terraform apply
```

During `terraform apply`, Terraform will:
1. Validate the existing VPC meets requirements
2. Create EKS, EC2, and RDS resources in your VPC
3. Display validation messages during apply

### Step 4: Continue with Normal Deployment

The rest of the deployment process remains the same:
- Build and push Docker images
- Deploy Dynatrace Operator
- Deploy Kubernetes applications
- Deploy EC2 applications

## VPC Requirements

Your existing VPC must have:

| Requirement | Status | Description |
|------------|--------|-------------|
| DNS Support | **Required** | EKS requires DNS support enabled |
| DNS Hostnames | **Required** | EKS requires DNS hostnames enabled |
| Public Subnets | **2+ Required** | Must be in different Availability Zones |
| Private Subnets | **2+ Required** | Must be in different Availability Zones |
| Internet Gateway | **Required** | Must be attached to VPC |
| NAT Gateway(s) | **Recommended** | Required for private subnet internet access |
| Public Subnet Tag | **Recommended** | `kubernetes.io/role/elb = 1` |
| Private Subnet Tag | **Recommended** | `kubernetes.io/role/internal-elb = 1` |

### Why These Requirements?

- **2+ Subnets per Type**: EKS requires resources spread across at least 2 AZs for high availability
- **DNS Settings**: EKS uses DNS for service discovery and pod communications
- **Internet Gateway**: Public Load Balancers need internet connectivity
- **NAT Gateway**: EKS nodes in private subnets need internet for:
  - Pulling container images from ECR
  - Communicating with Dynatrace SaaS
  - Downloading OneAgent
  - Accessing AWS APIs

## Benefits

### Using Existing VPC
- ✅ Avoid AWS VPC limits (5 VPCs per region by default)
- ✅ Reuse existing network infrastructure
- ✅ Integrate with existing VPNs, Direct Connect, or Transit Gateway
- ✅ Maintain existing security groups and NACLs
- ✅ Use established IP addressing schemes

### Creating New VPC (Original Behavior)
- ✅ Clean, isolated environment for demo
- ✅ No conflicts with existing resources
- ✅ Automatically configured with best practices
- ✅ Easier to clean up (destroy everything)

## Troubleshooting

### Validation Script Fails

If `validate-vpc.sh` reports errors:

1. **DNS Settings Not Enabled**
   ```bash
   aws ec2 modify-vpc-attribute --vpc-id vpc-xxxxx --enable-dns-support
   aws ec2 modify-vpc-attribute --vpc-id vpc-xxxxx --enable-dns-hostnames
   ```

2. **Missing Subnet Tags**
   ```bash
   # For public subnets
   aws ec2 create-tags --resources subnet-xxxxx --tags Key=kubernetes.io/role/elb,Value=1
   
   # For private subnets
   aws ec2 create-tags --resources subnet-xxxxx --tags Key=kubernetes.io/role/internal-elb,Value=1
   ```

3. **Not Enough Subnets**
   - Create additional public/private subnets in different AZs
   - Ensure route tables are properly configured

4. **No NAT Gateway**
   - Create NAT Gateway in public subnet
   - Update private subnet route tables to use NAT Gateway

### Terraform Apply Fails

If Terraform fails during apply:

1. **Check validation output** - Terraform will run validation during apply
2. **Verify subnet IDs** - Ensure IDs in terraform.tfvars match your AWS resources
3. **Check subnet AZs** - Subnets must span at least 2 different AZs
4. **Review AWS quotas** - Ensure you have capacity for EKS, EC2, RDS resources

### Post-Deployment Issues

If deployment succeeds but services don't work:

1. **EKS nodes can't pull images**
   - Verify NAT Gateway is working
   - Check private subnet route tables have route to NAT Gateway

2. **Load Balancer doesn't get created**
   - Verify public subnets have Internet Gateway route
   - Check subnet tags are set correctly

3. **Dynatrace not receiving data**
   - Verify outbound internet connectivity from private subnets
   - Check security groups allow outbound HTTPS traffic

## Backward Compatibility

This change is **fully backward compatible**:

- Default behavior: `use_existing_vpc = false` (creates new VPC)
- Existing terraform.tfvars files work without modification
- All existing automation scripts continue to work
- No breaking changes to outputs or module interfaces

## Files Changed

```
Modified:
  infra/terraform/variables.tf          # Added new variables
  infra/terraform/main.tf               # Conditional VPC module
  infra/terraform/outputs.tf            # Use local values
  infra/terraform/terraform.tfvars.example  # Added examples
  docs/SETUP.md                         # Added VPC section
  scripts/README.md                     # Documented new script
  README.md                             # Updated Quick Start

Created:
  infra/terraform/data.tf               # Data sources and validation
  scripts/validate-vpc.sh               # VPC validation tool
  EXISTING_VPC_GUIDE.md                 # This file

Permissions:
  scripts/validate-vpc.sh               # Made executable (chmod +x)
```

## Testing Recommendations

Before using in production:

1. **Test with validation script**
   ```bash
   ./scripts/validate-vpc.sh vpc-xxxxx us-east-1
   ```

2. **Run Terraform plan**
   ```bash
   terraform plan  # Review what will be created
   ```

3. **Test in non-production VPC first**
   - Use a test/dev VPC for initial deployment
   - Verify all services deploy correctly
   - Test connectivity and observability

4. **Cleanup test deployment**
   ```bash
   ./scripts/cleanup.sh  # Removes all created resources, not the VPC
   ```

## Next Steps

1. Run the validation script on your existing VPC
2. Review the validation output
3. Fix any issues reported
4. Update terraform.tfvars with the provided configuration
5. Deploy using standard process
6. Test the deployment

For detailed instructions, see [docs/SETUP.md](docs/SETUP.md).

## Support

If you encounter issues:

1. Check validation script output for specific errors
2. Review AWS VPC requirements in documentation
3. Verify all prerequisites are met
4. Check Terraform error messages for details

The validation script provides detailed remediation commands for most common issues.
