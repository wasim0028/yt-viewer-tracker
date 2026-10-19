variable "role_name" {
  type = string
}

variable "github_repo" {
  description = "owner/name of the only repository allowed to assume the role"
  type        = string
}

variable "branch" {
  description = "Only workflow runs on this branch can assume the role"
  type        = string
  default     = "main"
}

variable "ecr_repository_arns" {
  description = "ECR repositories CI may push to"
  type        = list(string)
}

variable "create_oidc_provider" {
  description = <<-EOT
    An AWS account can have only one GitHub OIDC provider. Set true for the
    first app deployed to an account, and false for every app after that,
    which then reuses the existing provider instead of failing with
    EntityAlreadyExists.
  EOT
  type        = bool
  default     = true
}

variable "create_terraform_roles" {
  description = <<-EOT
    Also create two roles for a Terraform workflow:
      plan  - read-only, assumable only by pull_request runs
      apply - can change infrastructure, assumable only by jobs that run in
              the GitHub environment named by apply_environment (protect
              that environment with required reviewers)
  EOT
  type        = bool
  default     = false
}

variable "iam_name_prefix" {
  description = "The apply role may only manage IAM roles/policies whose names start with this"
  type        = string
  default     = ""
}

variable "secret_name_prefix" {
  description = "The plan role may read Secrets Manager secrets under this prefix (needed to refresh them)"
  type        = string
  default     = ""
}

variable "apply_environment" {
  description = "GitHub environment whose jobs may assume the apply role"
  type        = string
  default     = "production"
}
