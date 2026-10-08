terraform {

    required_version = "~> 1.6"

    # State lives in S3 so CI runners (which are wiped after every run) and
    # your own machine share one source of truth. The bucket, lock table and
    # the role CI uses are created once by deployment/scripts/bootstrap.sh,
    # OUTSIDE this stack, so a destroy never deletes its own state.
    # Bucket, key, region and lock table are passed by 'deploy.sh init'.
    backend "s3" {}

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
