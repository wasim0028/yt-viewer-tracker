# Lets GitHub Actions push to ECR without any stored AWS access keys.

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  provider_arn = (var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
  : data.aws_iam_openid_connect_provider.github[0].arn)
}

data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "${local.github_oidc_url}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = local.github_oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = local.github_oidc_url
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only pushes to this branch of this repo. Forks and other branches
    # cannot assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.branch}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action has no resource-level scoping
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${var.role_name}-ecr-push"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# ---------------------------------------------------------------------------
# Optional: roles for a Terraform workflow (plan on PR, apply after approval)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  arn_pfx = "arn:${data.aws_partition.current.partition}"
}

data "aws_iam_policy_document" "terraform_plan_assume" {
  count = var.create_terraform_roles ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
    }
  }
}

resource "aws_iam_role" "terraform_plan" {
  count              = var.create_terraform_roles ? 1 : 0
  name               = "${var.role_name}-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.terraform_plan_assume[0].json
}

resource "aws_iam_role_policy_attachment" "terraform_plan_readonly" {
  count      = var.create_terraform_roles ? 1 : 0
  role       = aws_iam_role.terraform_plan[0].name
  policy_arn = "${local.arn_pfx}:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess can't read secret values, but refreshing a secret version
# during plan needs to.
data "aws_iam_policy_document" "terraform_plan_secrets" {
  count = var.create_terraform_roles ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["${local.arn_pfx}:secretsmanager:${data.aws_region.current.name}:${local.account}:secret:${var.secret_name_prefix}*"]
  }
}

resource "aws_iam_role_policy" "terraform_plan_secrets" {
  count  = var.create_terraform_roles ? 1 : 0
  name   = "read-project-secrets"
  role   = aws_iam_role.terraform_plan[0].id
  policy = data.aws_iam_policy_document.terraform_plan_secrets[0].json
}

data "aws_iam_policy_document" "terraform_apply_assume" {
  count = var.create_terraform_roles ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${var.apply_environment}"]
    }
  }
}

resource "aws_iam_role" "terraform_apply" {
  count              = var.create_terraform_roles ? 1 : 0
  name               = "${var.role_name}-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.terraform_apply_assume[0].json
}

# Everything except IAM, Organizations, and Account management.
resource "aws_iam_role_policy_attachment" "terraform_apply_poweruser" {
  count      = var.create_terraform_roles ? 1 : 0
  role       = aws_iam_role.terraform_apply[0].name
  policy_arn = "${local.arn_pfx}:iam::aws:policy/PowerUserAccess"
}

# IAM, but only for this project's own roles and policies (name prefix),
# plus OIDC providers. Note: a role that can create IAM roles can in
# principle grant itself more access, so the prefix limits accidents, not
# a determined attacker. The real control is the environment approval gate.
data "aws_iam_policy_document" "terraform_apply_iam" {
  count = var.create_terraform_roles ? 1 : 0

  statement {
    sid     = "ManageProjectIam"
    actions = ["iam:*"]
    resources = [
      "${local.arn_pfx}:iam::${local.account}:role/${var.iam_name_prefix}*",
      "${local.arn_pfx}:iam::${local.account}:policy/${var.iam_name_prefix}*",
      "${local.arn_pfx}:iam::${local.account}:instance-profile/${var.iam_name_prefix}*",
    ]
  }

  statement {
    sid = "ManageOidcProviders"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviderTags",
    ]
    resources = ["${local.arn_pfx}:iam::${local.account}:oidc-provider/*"]
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_apply_iam" {
  count  = var.create_terraform_roles ? 1 : 0
  name   = "manage-project-iam"
  role   = aws_iam_role.terraform_apply[0].id
  policy = data.aws_iam_policy_document.terraform_apply_iam[0].json
}
