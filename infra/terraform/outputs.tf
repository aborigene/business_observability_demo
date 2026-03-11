output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "tier3_ec2_public_ip" {
  description = "Tier 3 (C Legacy) EC2 public IP"
  value       = module.tier3_ec2.public_ip
}

output "tier3_ec2_private_ip" {
  description = "Tier 3 (C Legacy) EC2 private IP"
  value       = module.tier3_ec2.private_ip
}

output "tier5_ec2_public_ip" {
  description = "Tier 5 (.NET) EC2 public IP"
  value       = module.tier5_ec2.public_ip
}

output "tier5_ec2_private_ip" {
  description = "Tier 5 (.NET) EC2 private IP"
  value       = module.tier5_ec2.private_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.db_endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "next_steps" {
  description = "Next steps after infrastructure provisioning"
  value = <<-EOT
    
    ========================================
    Infrastructure Provisioned Successfully!
    ========================================
    
    1. Configure kubectl:
       ${module.eks.configure_kubectl_command}
    
    2. SSH to Tier 3 EC2:
       ssh ec2-user@${module.tier3_ec2.public_ip}
    
    3. SSH to Tier 5 EC2:
       ssh ec2-user@${module.tier5_ec2.public_ip}
    
    4. Install Dynatrace Operator in EKS:
       kubectl apply -f ../../k8s/dynatrace-operator/
    
    5. Deploy applications to Kubernetes:
       kubectl apply -f ../../k8s/
    
    6. Database connection:
       Host: ${module.rds.db_endpoint}
       Database: ${module.rds.db_name}
       Username: ${var.db_username}
    
    See docs/SETUP.md for detailed instructions.
  EOT
}
