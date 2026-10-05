variable "name" {
  description = "IAM role and policy name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "From the eks-fargate module"
  type        = string
}

variable "oidc_provider" {
  description = "From the eks-fargate module (issuer without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account"
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account allowed to assume this role"
  type        = string
}

variable "policy_json" {
  description = "IAM policy document (JSON) with the permissions the pod needs"
  type        = string
}
