variable "environment" {
    description = "environment for stage , dev and prod"
    type = string
    default = "dev"
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  description = <<-EOT
    Optional. Set it with the environment variable TF_VAR_db_password,
    never in terraform.tfvars, so it is never committed. If unset, Terraform
    generates a strong password.
  EOT
  type        = string
  default     = null
  sensitive   = true

  validation {
    # Rules for RDS PostgreSQL master passwords. try() keeps this safe when
    # the value is null (no password supplied).
    condition = var.db_password == null || var.db_password == "" || try(
      length(var.db_password) >= 8 &&
      length(var.db_password) <= 128 &&
      !can(regex("[/@\" ]", var.db_password)),
      false
    )
    error_message = "The database password must be 8-128 characters and must not contain / @ \" or spaces (RDS rejects them)."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "eks_cluster_version" {
  type    = string
  default = "1.35"
}

variable "app_namespace" {
  description = "Kubernetes namespace the app runs in"
  type        = string
}

variable "extra_fargate_namespaces" {
  description = "Namespaces besides the app's and the platform ones that need Fargate"
  type        = list(string)
  default     = []
}

variable "api_key_names" {
  description = "Keys in the api-keys secret that you fill in by hand"
  type        = list(string)
}

variable "ecr_repositories" {
  description = "One ECR repository per image, e.g. [\"backend\", \"frontend\"]"
  type        = list(string)
}


variable "github_repo" {
  description = "owner/name; the only repo whose CI can push images"
  type        = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "create_github_oidc_provider" {
  description = "true for the first app in an AWS account, false for every later app"
  type        = bool
  default     = true
}

