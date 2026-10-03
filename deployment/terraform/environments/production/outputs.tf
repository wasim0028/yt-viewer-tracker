# bootstrap.sh reads these by name. Keep the names stable.

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "Passed to the Load Balancer Controller (required on Fargate)"
  value       = module.vpc.vpc_id
}

output "rds_endpoint" {
  description = "host:port only. The full connection string is in Secrets Manager."
  value       = module.rds.endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecr_backend_repository_url" {
  value = module.ecr.repository_urls["backend"]
}

output "ecr_frontend_repository_url" {
  value = module.ecr.repository_urls["frontend"]
}

output "database_url_secret_name" {
  value = module.app_secrets.database_url_secret_name
}

output "api_keys_secret_name" {
  value = module.app_secrets.api_keys_secret_name
}

output "external_secrets_role_arn" {
  value = module.external_secrets_irsa.role_arn
}

output "adot_collector_role_arn" {
  value = module.adot_collector_irsa.role_arn
}

output "lb_controller_role_arn" {
  value = module.lb_controller_irsa.role_arn
}

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}

output "amp_workspace_endpoint" {
  value = module.prometheus.endpoint
}

output "amp_workspace_query_endpoint" {
  description = "Point Grafana's Prometheus data source here"
  value       = "${module.prometheus.endpoint}api/v1/query"
}
