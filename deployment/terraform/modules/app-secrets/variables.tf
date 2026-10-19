variable "name_prefix" {
  description = "Secrets are created as <name_prefix>/database-url and <name_prefix>/api-keys"
  type        = string
}

variable "database_url" {
  description = "Full connection string, built by the caller from the RDS outputs"
  type        = string
  sensitive   = true
}

variable "api_key_names" {
  description = "Keys stored in the api-keys secret, filled in by hand after apply"
  type        = list(string)
}

variable "recovery_window_in_days" {
  description = "How long a deleted secret can be restored. 0 deletes immediately."
  type        = number
  default     = 7
}
