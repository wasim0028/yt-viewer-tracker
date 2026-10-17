output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "Pass to the irsa-role module"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC issuer without https://, used in IRSA trust conditions"
  value       = module.eks.oidc_provider
}

output "cluster_primary_security_group_id" {
  description = "Security group Fargate pods use; allow it into the database"
  value       = module.eks.cluster_primary_security_group_id
}

output "fargate_pod_execution_role_name" {
  description = "Role Fargate uses to pull images and ship container logs"
  value       = aws_iam_role.fargate_pod_execution.name
}
