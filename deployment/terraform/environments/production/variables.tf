# Values are set in terraform.tfvars. Defaults here are only fallbacks.

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  description = "Short app name; prefixes every resource"
  type        = string
}

variable "environment" {
  type    = string
  default = "production"
}

variable "vpc_cidr" {
  description = "Use a different range per app if their VPCs may ever be peered"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  type = list(string)
}

variable "eks_cluster_version" {
  type    = string
  default = "1.30"
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

variable "ecr_repositories" {
  description = "One ECR repository per image, e.g. [\"backend\", \"frontend\"]"
  type        = list(string)
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
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

variable "api_key_names" {
  description = "Keys in the api-keys secret that you fill in by hand"
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
