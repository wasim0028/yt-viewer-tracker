variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  description = "Kubernetes version for the control plane"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the control plane ENIs and Fargate pods"
  type        = list(string)
}

variable "fargate_namespaces" {
  description = <<-EOT
    Namespaces that get a Fargate profile. Pods in any other namespace stay
    Pending. Always include kube-system, or CoreDNS has nowhere to run and
    in-cluster DNS breaks.
  EOT
  type        = list(string)
}
