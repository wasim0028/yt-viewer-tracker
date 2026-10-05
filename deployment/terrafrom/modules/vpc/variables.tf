variable "name" {}

variable "environment" {}

variable "cidr_block" {
    description = "cidr block for vpc"
    type = string
    default = "10.0.0.0/16"
}

variable "public_subnets" {
    description = "public subnet cidr block"
    type = list(string)
    default = [ "10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24" ]
}

variable "private_subnets" {
    description = "private subnet cidr block"
    type = list(string)
    default = [ "10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24" ]
}

variable "azs" {}

variable "cluster_name" {
  description = "EKS cluster name, used for the subnet tags the Load Balancer Controller looks for"
  type        = string
}

