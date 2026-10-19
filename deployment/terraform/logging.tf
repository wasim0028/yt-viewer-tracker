# Container logs from Fargate pods.
#
# EKS Fargate's built-in Fluent Bit router (configured by
# k8s/base/aws-logging-configmap.yaml) ships stdout/stderr to CloudWatch using
# the Fargate POD EXECUTION role. AWS's managed
# AmazonEKSFargatePodExecutionRolePolicy has no CloudWatch Logs permissions,
# so without the policy below nothing is ever written and the log group never
# appears.
#
# The log group is created here (not left to Fluent Bit's auto_create_group)
# so it has a retention period and is deleted on destroy.

locals {
  # Must match log_group_name in k8s/base/aws-logging-configmap.yaml.
  fargate_log_group_name = "/aws/eks/${local.name}-production/fargate"
}

resource "aws_cloudwatch_log_group" "fargate" {
  name              = local.fargate_log_group_name
  retention_in_days = 30
}

data "aws_iam_policy_document" "fargate_logging" {
  statement {
    sid = "ShipContainerLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
    ]
    resources = [
      aws_cloudwatch_log_group.fargate.arn,
      "${aws_cloudwatch_log_group.fargate.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "fargate_logging" {
  name   = "fargate-container-logs"
  role   = module.eks.fargate_pod_execution_role_name
  policy = data.aws_iam_policy_document.fargate_logging.json
}

output "fargate_log_group" {
  value = aws_cloudwatch_log_group.fargate.name
}
