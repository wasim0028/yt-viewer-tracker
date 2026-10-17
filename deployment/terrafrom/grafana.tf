# Self-hosted Grafana: reads metrics from Amazon Managed Prometheus.
#
# Two things Terraform owns for it:
#   1. A least-privilege IAM role (IRSA) that can only QUERY the workspace.
#   2. The admin password, generated here and stored in Secrets Manager so
#      External Secrets can hand it to the pod. It never appears in git.

data "aws_iam_policy_document" "grafana" {
  statement {
    actions   = ["aps:QueryMetrics", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [module.prometheus.workspace_arn]
  }
}

module "grafana_irsa" {
  source = "./modules/irsa-role"

  name              = "${local.name}-grafana"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = var.app_namespace
  service_account   = "grafana"
  policy_json       = data.aws_iam_policy_document.grafana.json
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false # keeps the password safe to paste into a login form and a shell
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name        = "${local.name}/grafana-admin"
  description = "Grafana admin login. Managed by Terraform."
  # 0 = delete immediately on destroy, so a redeploy never hits the
  # 7-day "scheduled for deletion" name reservation.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id     = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({ GF_SECURITY_ADMIN_PASSWORD = random_password.grafana_admin.result })
}

output "grafana_role_arn" {
  value = module.grafana_irsa.role_arn
}

output "grafana_admin_secret_name" {
  value = aws_secretsmanager_secret.grafana_admin.name
}
