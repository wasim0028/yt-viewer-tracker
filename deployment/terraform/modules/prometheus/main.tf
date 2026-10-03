# Amazon Managed Service for Prometheus. Used instead of a self-hosted
# Prometheus server because Fargate can't attach the persistent volume a
# Prometheus server needs for its data.

resource "aws_prometheus_workspace" "this" {
  alias = var.alias
}
