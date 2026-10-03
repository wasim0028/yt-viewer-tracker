# EKS cluster that runs entirely on Fargate: no EC2 node groups to patch.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # API endpoint reachable from your machine and CI; pods stay private.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Lets individual pods assume their own IAM roles (IRSA).
  enable_irsa = true

  # Grants the IAM identity that runs Terraform admin access to the cluster.
  # Module v20 defaults this to false, which makes every kubectl command
  # fail with "Unauthorized", including the ones in bootstrap.sh.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {}
}

# Role AWS uses to start Fargate pods (pull the image, write logs).
data "aws_iam_policy_document" "fargate_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fargate_pod_execution" {
  name               = "${var.cluster_name}-fargate-pod-execution"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume_role.json
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# The policy above has no ECR read access. Without this, pods fail with
# ImagePullBackOff when pulling from your own ECR repositories.
resource "aws_iam_role_policy_attachment" "fargate_pod_execution_ecr" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_fargate_profile" "this" {
  for_each = toset(var.fargate_namespaces)

  cluster_name           = module.eks.cluster_name
  fargate_profile_name   = each.value
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.subnet_ids

  selector {
    namespace = each.value
  }
}
