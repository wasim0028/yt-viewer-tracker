# Everything specific to this application. To deploy another app, copy this
# whole environments/production folder and change these values.
# Nothing in this file is secret, so it is safe to commit.

aws_region         = "ap-south-1"
project_name       = "yt-viewer-tracker"
environment        = "production"
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

eks_cluster_version = "1.30"
app_namespace       = "yt-viewer-tracker"

ecr_repositories = ["backend", "frontend"]

db_name                 = "yt_viewer_tracker"
db_username             = "yt_viewer_admin"
db_instance_class       = "db.t4g.micro"
db_allocated_storage_gb = 20
db_multi_az             = false

api_key_names = ["YOUTUBE_API_KEY", "ADS_API_KEY"]

github_repo                 = "wasim0028/yt-viewer-tracker"
github_branch               = "main"
create_github_oidc_provider = true
