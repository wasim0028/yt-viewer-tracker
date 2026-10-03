terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.60" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Recommended: keep state in S3 so it isn't lost with your laptop. Create
  # the bucket and DynamoDB table first, then uncomment and fill in.
  # Use a different "key" for every application/environment.
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "yt-viewer-tracker/production/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "your-terraform-lock-table"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  # Tags every resource, so costs can be split per app in AWS Billing.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
