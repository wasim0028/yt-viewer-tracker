terraform {

    required_version = "~> 1.6"

    required_providers {
        aws = {
                source = "hashicorp/aws"
                version = "~> 5.6"
        } 

        kubernetes = {
                source = "hashicorp/kubernetes"
                version = "~> 2.25"
        }

        helm = {
                source = "hashicorp/helm"
                version = "~> 2.12"
        }
    }

}

provider "aws" {
    region = "ap-south-1"

    default_tags {
        tags = {
            project = "Yt-viewer-tracker"
            environment = var.environment
            ManagedBy = "Terraform"
            Owner = "DevOps_Team"
        }
    }
}

resource "aws_s3_bucket" "terraform-state" {
    bucket = "${local.name}-${local.account_id}"
    force_destroy = false
}

resource "aws_s3_bucket_versioning" "state_versioning" {
    bucket = aws_s3_bucket.terraform-state.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_public_access_block" "state_privacy" {
    bucket = aws_s3_bucket.terraform-state.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
    name = "mystate_table"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
}

