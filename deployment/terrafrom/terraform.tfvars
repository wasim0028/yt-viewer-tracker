aws_region       = "ap-south-1"
app_namespace    = "yt-viewer-tracker"
ecr_repositories = ["backend", "frontend"]
db_name          = "yt_viewer_tracker"
db_username      = "yt_viewer_admin"
api_key_names    = ["YOUTUBE_API_KEY", "ADS_API_KEY"]
github_repo      = "wasim0028/yt-viewer-tracker"

# bootstrap.sh already created the account-wide GitHub OIDC provider
create_github_oidc_provider = false
github_branch               = "devops"
