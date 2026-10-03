variable "name" {
  description = "Name prefix for every resource in this module"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the VPC, e.g. 10.20.0.0/16"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (EKS needs at least 2)"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name, used for the subnet tags the Load Balancer Controller looks for"
  type        = string
}
