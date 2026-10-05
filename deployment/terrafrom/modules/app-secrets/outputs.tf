output "database_url_secret_name" {
  value = aws_secretsmanager_secret.database_url.name
}

output "api_keys_secret_name" {
  value = aws_secretsmanager_secret.api_keys.name
}

output "secret_arns" {
  description = "Both secret ARNs, for granting read access"
  value = [
    aws_secretsmanager_secret.database_url.arn,
    aws_secretsmanager_secret.api_keys.arn,
  ]
}
