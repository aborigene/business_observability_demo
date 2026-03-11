# Data sources for existing VPC (when use_existing_vpc = true)

data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_subnet" "existing_public" {
  count = var.use_existing_vpc ? length(var.existing_public_subnet_ids) : 0
  id    = var.existing_public_subnet_ids[count.index]
}

data "aws_subnet" "existing_private" {
  count = var.use_existing_vpc ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]
}

data "aws_internet_gateway" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  
  filter {
    name   = "attachment.vpc-id"
    values = [var.existing_vpc_id]
  }
}

data "aws_nat_gateways" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  
  vpc_id = var.existing_vpc_id
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Validation checks for existing VPC
resource "null_resource" "validate_existing_vpc" {
  count = var.use_existing_vpc ? 1 : 0
  
  triggers = {
    vpc_id               = var.existing_vpc_id
    public_subnet_count  = length(var.existing_public_subnet_ids)
    private_subnet_count = length(var.existing_private_subnet_ids)
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      echo "=== VPC Validation Results ==="
      echo "VPC ID: ${var.existing_vpc_id}"
      echo "VPC CIDR: ${data.aws_vpc.existing[0].cidr_block}"
      echo "DNS Support: ${data.aws_vpc.existing[0].enable_dns_support}"
      echo "DNS Hostnames: ${data.aws_vpc.existing[0].enable_dns_hostnames}"
      echo "Public Subnets: ${length(var.existing_public_subnet_ids)}"
      echo "Private Subnets: ${length(var.existing_private_subnet_ids)}"
      echo ""
      
      # Check public subnets
      if [ ${length(var.existing_public_subnet_ids)} -lt 2 ]; then
        echo "ERROR: At least 2 public subnets are required for EKS and Load Balancers"
        exit 1
      fi
      
      # Check private subnets
      if [ ${length(var.existing_private_subnet_ids)} -lt 2 ]; then
        echo "ERROR: At least 2 private subnets are required for EKS node groups"
        exit 1
      fi
      
      # Check DNS support
      if [ "${data.aws_vpc.existing[0].enable_dns_support}" = "false" ]; then
        echo "ERROR: VPC must have DNS support enabled"
        exit 1
      fi
      
      # Check DNS hostnames
      if [ "${data.aws_vpc.existing[0].enable_dns_hostnames}" = "false" ]; then
        echo "ERROR: VPC must have DNS hostnames enabled"
        exit 1
      fi
      
      # Check NAT Gateways (warning only)
      NAT_COUNT=${length(data.aws_nat_gateways.existing[0].ids)}
      if [ $NAT_COUNT -lt 1 ]; then
        echo "WARNING: No NAT Gateways found. Private subnets need NAT for internet access."
        echo "EKS nodes may not be able to pull container images or communicate with Dynatrace."
      else
        echo "NAT Gateways: $NAT_COUNT"
      fi
      
      echo ""
      echo "=== VPC Validation Passed ==="
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
  
  depends_on = [
    data.aws_vpc.existing,
    data.aws_subnet.existing_public,
    data.aws_subnet.existing_private
  ]
}

# Local values to abstract VPC source
locals {
  vpc_id             = var.use_existing_vpc ? var.existing_vpc_id : module.vpc[0].vpc_id
  public_subnet_ids  = var.use_existing_vpc ? var.existing_public_subnet_ids : module.vpc[0].public_subnet_ids
  private_subnet_ids = var.use_existing_vpc ? var.existing_private_subnet_ids : module.vpc[0].private_subnet_ids
  vpc_cidr           = var.use_existing_vpc ? data.aws_vpc.existing[0].cidr_block : module.vpc[0].vpc_cidr
}
