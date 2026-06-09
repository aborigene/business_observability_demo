terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "business-observability-demo"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module (conditional - only create if not using existing)
module "vpc" {
  count  = var.use_existing_vpc ? 0 : 1
  source = "./modules/vpc"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

# EKS Module (conditional - only create if not using existing)
module "eks" {
  count  = var.use_existing_eks ? 0 : 1
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = local.vpc_id
  private_subnet_ids  = local.private_subnet_ids
  eks_cluster_version = var.eks_cluster_version
  created_by          = var.created_by
}

# RDS PostgreSQL Module
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids
  db_username        = var.db_username
  db_password        = var.db_password
  db_name            = var.db_name
  vpc_cidr           = local.vpc_cidr
}
