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

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

# EKS Module
module "eks" {
  source = "./modules/eks"
  
  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  eks_cluster_version = var.eks_cluster_version
}

# RDS PostgreSQL Module
module "rds" {
  source = "./modules/rds"
  
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_username        = var.db_username
  db_password        = var.db_password
  db_name            = var.db_name
  allowed_security_group_ids = [
    module.tier5_ec2.security_group_id
  ]
}

# EC2 for Tier 3 (C Legacy)
module "tier3_ec2" {
  source = "./modules/ec2"
  
  project_name       = var.project_name
  environment        = var.environment
  name_suffix        = "tier3-risk-analysis"
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnet_ids[0]
  instance_type      = var.tier3_instance_type
  user_data_template = file("${path.module}/userdata/tier3-userdata.sh")
  user_data_vars = {
    dt_env_url    = var.dt_env_url
    dt_paas_token = var.dt_paas_token
    tier4_host    = "tier4-service.${var.project_name}.svc.cluster.local"
    tier4_port    = "8001"
  }
  ingress_rules = [
    {
      from_port   = 8000
      to_port     = 8000
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
      description = "Allow HTTP from VPC"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow SSH"
    }
  ]
}

# EC2 for Tier 5 (.NET)
module "tier5_ec2" {
  source = "./modules/ec2"
  
  project_name       = var.project_name
  environment        = var.environment
  name_suffix        = "tier5-loan-finalizer"
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnet_ids[0]
  instance_type      = var.tier5_instance_type
  user_data_template = file("${path.module}/userdata/tier5-userdata.sh")
  user_data_vars = {
    dt_env_url   = var.dt_env_url
    dt_paas_token = var.dt_paas_token
    database_url = "Host=${module.rds.db_endpoint};Port=5432;Database=${var.db_name};Username=${var.db_username};Password=${var.db_password}"
    base_rate    = "0.02"
  }
  ingress_rules = [
    {
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
      description = "Allow HTTP from VPC"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow SSH"
    }
  ]
}
