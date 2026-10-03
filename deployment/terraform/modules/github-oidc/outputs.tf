output "role_arn" {
  description = "Use as role-to-assume in the GitHub Actions workflow"
  value       = aws_iam_role.this.arn
}
