variable "identifier" {
  description = "RDS instance identifier, also used to name related resources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the database"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on port 5432 (e.g. the EKS cluster's)"
  type        = list(string)
}

variable "db_name" {
  type = string
}

variable "username" {
  type = string
}

variable "engine_version" {
  description = "Major version only (e.g. \"16\"): AWS picks the current minor. Pinned minors get retired."
  type        = string
  default     = "16"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "multi_az" {
  description = "Standby in a second AZ. Costs about double; turn on for real production traffic."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}
