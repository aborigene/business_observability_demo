variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for naming resources"
  type        = string
  default     = "loan-demo"
}

variable "environment" {
  description = "Environment (dev, demo, prod)"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (only used when create_vpc = true)"
  type        = string
  default     = "10.0.0.0/16"
}

# Existing VPC Configuration
variable "use_existing_vpc" {
  description = "Whether to use an existing VPC instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use (required if use_existing_vpc = true)"
  type        = string
  default     = ""
}

variable "existing_public_subnet_ids" {
  description = "List of existing public subnet IDs (required if use_existing_vpc = true)"
  type        = list(string)
  default     = []
}

variable "existing_private_subnet_ids" {
  description = "List of existing private subnet IDs (required if use_existing_vpc = true)"
  type        = list(string)
  default     = []
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

variable "tier3_instance_type" {
  description = "EC2 instance type for Tier 3"
  type        = string
  default     = "t3.small"
}

variable "tier5_instance_type" {
  description = "EC2 instance type for Tier 5"
  type        = string
  default     = "t3.small"
}

# Database variables
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "loandb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "loanadmin"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

# Dynatrace variables
variable "dt_env_url" {
  description = "Dynatrace environment URL (e.g., https://abc12345.live.dynatrace.com)"
  type        = string
}

variable "dt_paas_token" {
  description = "Dynatrace PaaS token for OneAgent installation"
  type        = string
  sensitive   = true
}

variable "dt_api_token" {
  description = "Dynatrace API token for Business Events ingest"
  type        = string
  sensitive   = true
}
