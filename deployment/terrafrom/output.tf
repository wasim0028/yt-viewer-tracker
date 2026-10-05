output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "ecr_backend_repository_url" {
  value = module.ecr.repository_urls["backend"]
}

output "ecr_frontend_repository_url" {
  value = module.ecr.repository_urls["frontend"]
}

output "api_keys_secret_name" {
  value = module.app_secrets.api_keys_secret_name
}

output "database_url_secret_name" {
  value = module.app_secrets.database_url_secret_name
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

output "github_terraform_plan_role_arn" {
  value = module.github_oidc.terraform_plan_role_arn
}

output "github_terraform_apply_role_arn" {
  value = module.github_oidc.terraform_apply_role_arn
}

output "amp_workspace_endpoint" {
  value = module.prometheus.endpoint
}

output "tf_state_bucket" {
  value = aws_s3_bucket.terraform-state.bucket
}
