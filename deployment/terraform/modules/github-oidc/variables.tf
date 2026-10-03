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
