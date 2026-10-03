# yt-viewer-tracker / production
#
# This file only connects the reusable modules in ../../modules. All
# app-specific values come from terraform.tfvars.

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Platform namespaces every cluster built this way needs on Fargate.
  fargate_namespaces = distinct(concat(
    ["kube-system", "external-secrets", "argocd", "aws-observability", var.app_namespace],
    var.extra_fargate_namespaces,
  ))
}

module "vpc" {
  source = "../../modules/vpc"

  name         = local.name_prefix
  cidr         = var.vpc_cidr
  azs          = var.availability_zones
  cluster_name = local.name_prefix
}

module "eks" {
  source = "../../modules/eks-fargate"

  cluster_name       = local.name_prefix
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  fargate_namespaces = local.fargate_namespaces
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix  = var.project_name
  repositories = var.ecr_repositories
}

module "rds" {
  source = "../../modules/rds-postgres"

  identifier                 = "${local.name_prefix}-db"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_primary_security_group_id]
  db_name                    = var.db_name
  username                   = var.db_username
  instance_class             = var.db_instance_class
  allocated_storage_gb       = var.db_allocated_storage_gb
  multi_az                   = var.db_multi_az
}

module "app_secrets" {
  source = "../../modules/app-secrets"

  name_prefix = local.name_prefix
  # urlencode() matters: the generated password can contain # or @, which
  # would otherwise break the URL and silently truncate it.
  database_url  = "postgres://${module.rds.username}:${urlencode(module.rds.password)}@${module.rds.endpoint}/${module.rds.db_name}"
  api_key_names = var.api_key_names
}

module "prometheus" {
  source = "../../modules/prometheus"

  alias = local.name_prefix
}

# ---- IRSA roles: one per in-cluster component that calls AWS ----

data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = module.app_secrets.secret_arns
  }
}

module "external_secrets_irsa" {
  source = "../../modules/irsa-role"

  name              = "${local.name_prefix}-external-secrets"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "external-secrets"
  service_account   = "external-secrets-sa"
  policy_json       = data.aws_iam_policy_document.external_secrets.json
}

data "aws_iam_policy_document" "adot_collector" {
  statement {
    actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [module.prometheus.workspace_arn]
  }
}

module "adot_collector_irsa" {
  source = "../../modules/irsa-role"

  name              = "${local.name_prefix}-adot-collector"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = var.app_namespace
  service_account   = "adot-collector"
  policy_json       = data.aws_iam_policy_document.adot_collector.json
}

# AWS's official policy, unmodified. Replace the file if you upgrade the
# controller's Helm chart to a newer version.
module "lb_controller_irsa" {
  source = "../../modules/irsa-role"

  name              = "${local.name_prefix}-lb-controller"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_json       = file("${path.module}/../../policies/aws-load-balancer-controller-v2.11.0.json")
}

# ---- CI: GitHub Actions pushes images with no stored AWS keys ----

module "github_oidc" {
  source = "../../modules/github-oidc"

  role_name            = "${local.name_prefix}-github-actions"
  github_repo          = var.github_repo
  branch               = var.github_branch
  ecr_repository_arns  = values(module.ecr.repository_arns)
  create_oidc_provider = var.create_github_oidc_provider
}
