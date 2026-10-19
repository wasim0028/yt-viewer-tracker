output "role_arn" {
  description = "Use as role-to-assume in the GitHub Actions workflow"
  value       = aws_iam_role.this.arn
}

output "terraform_plan_role_arn" {
  value = var.create_terraform_roles ? aws_iam_role.terraform_plan[0].arn : null
}

output "terraform_apply_role_arn" {
  value = var.create_terraform_roles ? aws_iam_role.terraform_apply[0].arn : null
}
