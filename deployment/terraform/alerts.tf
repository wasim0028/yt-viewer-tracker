# Alerting for the backend: Prometheus rules -> Alertmanager (both inside
# Amazon Managed Prometheus) -> SNS topic -> your email.
#
# Set the address with  TF_VAR_alert_email  (the Deploy workflow reads the
# GitHub repo variable ALERT_EMAIL). AWS sends a confirmation email to that
# address once; the subscription stays "pending" until you click the link.
# Leave it empty to create the rules and topic without an email subscriber.

variable "alert_email" {
  description = "Where alerts are emailed. Empty = no email subscription."
  type        = string
  default     = ""
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

# Lets the Managed Prometheus Alertmanager (and only this workspace) publish.
data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AllowManagedPrometheusToPublish"
    actions   = ["sns:Publish", "sns:GetTopicAttributes"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["aps.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.prometheus.workspace_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---- What counts as a problem ----
resource "aws_prometheus_rule_group_namespace" "backend" {
  name         = "viewer-watch-backend"
  workspace_id = module.prometheus.workspace_id

  data = <<-EOT
    groups:
      - name: viewer-watch-backend
        rules:
          # up == 0: the scrape failed. absent(): no data at all, which also
          # covers the collector itself being down (a dead scraper cannot
          # report "up == 0", so this is the case a plain == 0 would miss).
          - alert: BackendDown
            expr: up{job="backend"} == 0 or absent(up{job="backend"})
            for: 3m
            labels:
              severity: critical
            annotations:
              summary: "Viewer Watch backend is down or not reporting metrics"
              description: "No successful scrape of the backend for 3 minutes. Check the backend pod and the ADOT collector."

          # The pod limit is 256Mi; 200Mi sustained means an OOM kill is near.
          - alert: BackendHighMemory
            expr: process_resident_memory_bytes{job="backend"} > 200 * 1024 * 1024
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Backend memory above 200 MiB (limit 256 MiB)"
              description: "Resident memory has been high for 5 minutes; the pod may be OOM-killed soon."

          - alert: BackendEventLoopLag
            expr: nodejs_eventloop_lag_p99_seconds{job="backend"} > 0.5
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Backend event loop is slow (p99 above 0.5s)"
              description: "The Node.js event loop is blocked; requests and polling will be delayed."

          # More than 2 restarts in 30 minutes. One restart (a normal deploy)
          # does not trigger this, a crash loop does.
          - alert: BackendCrashLooping
            expr: changes(process_start_time_seconds{job="backend"}[30m]) > 2
            labels:
              severity: critical
            annotations:
              summary: "Backend restarted more than twice in 30 minutes"
              description: "The backend process keeps restarting. Check `kubectl logs` and `kubectl describe pod`."
  EOT
}

# ---- Where alerts go ----
resource "aws_prometheus_alert_manager_definition" "this" {
  workspace_id = module.prometheus.workspace_id

  definition = <<-EOT
    alertmanager_config: |
      route:
        receiver: sns
        group_by: ['alertname']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
      receivers:
        - name: sns
          sns_configs:
            - topic_arn: ${aws_sns_topic.alerts.arn}
              send_resolved: true
              sigv4:
                region: ${var.aws_region}
  EOT

  depends_on = [aws_sns_topic_policy.alerts]
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
