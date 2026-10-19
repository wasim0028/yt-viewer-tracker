variable "name_prefix" {
  description = "Prefix for repository names: \"my-app\" gives my-app-backend"
  type        = string
}

variable "repositories" {
  description = "Short repository names, e.g. [\"backend\", \"frontend\"]"
  type        = list(string)
}

variable "keep_last_images" {
  description = "Images beyond this count are deleted automatically, oldest first"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Let terraform destroy delete repositories that still contain images"
  type        = bool
  default     = false
}
