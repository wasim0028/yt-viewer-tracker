output "workspace_arn" {
  value = aws_prometheus_workspace.this.arn
}

output "endpoint" {
  description = "Base URL. Append api/v1/remote_write for writes, api/v1/query for queries."
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "workspace_id" {
  description = "Needed by the alerting resources (rule groups, Alertmanager)"
  value       = aws_prometheus_workspace.this.id
}
