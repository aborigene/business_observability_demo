output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "vpc_source" {
  description = "Whether VPC was created or existing was used"
  value       = var.use_existing_vpc ? "existing" : "created"
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = local.private_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = local.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = local.eks_cluster_endpoint
}

output "eks_source" {
  description = "Whether EKS cluster was created or existing was used"
  value       = var.use_existing_eks ? "existing" : "created"
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
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.eks_cluster_name}"
}

output "next_steps" {
  description = "Next steps after infrastructure provisioning"
  value = <<-EOT
    
    ========================================
    Infrastructure Provisioned Successfully!
    ========================================
    
    1. Configure kubectl:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${local.eks_cluster_name}

    2. Update k8s/tier5/02-secret.yaml with RDS endpoint:
       Host: ${module.rds.db_endpoint}
       Database: ${module.rds.db_name}
       Username: ${var.db_username}

    3. Install Dynatrace Operator:
       kubectl apply -f ../../k8s/dynatrace-operator/

    4. Build and push images, then deploy:
       ./scripts/build-images.sh && ./scripts/push-to-ecr.sh
       kubectl apply -f ../../k8s/

    See docs/SETUP.md for detailed instructions.
  EOT
}
