# Two secrets with opposite lifecycles, deliberately kept apart:
#
#   database-url  Owned by Terraform. Safe to update on every apply, so a
#                 rotated password flows through automatically.
#   api-keys      Owned by you. Terraform creates it once with placeholders
#                 and never touches it again (ignore_changes), so your real
#                 keys are never reset by a later apply.

locals {
  placeholder = "REPLACE_ME_VIA_AWS_CLI_NOT_TERRAFORM"
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.name_prefix}/database-url"
  description             = "PostgreSQL connection string. Managed by Terraform; do not edit by hand."
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = var.database_url
}

resource "aws_secretsmanager_secret" "api_keys" {
  name                    = "${var.name_prefix}/api-keys"
  description             = "External API keys. Set with the AWS CLI, never with Terraform."
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id     = aws_secretsmanager_secret.api_keys.id
  secret_string = jsonencode({ for k in var.api_key_names : k => local.placeholder })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
