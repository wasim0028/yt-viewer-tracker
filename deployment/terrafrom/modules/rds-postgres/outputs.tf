output "endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "password" {
  value     = local.master_password
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.this.id
}
