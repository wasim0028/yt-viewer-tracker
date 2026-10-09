#!/usr/bin/env bash
#
# bootstrap.sh - ONE-TIME setup so GitHub Actions can deploy for you.
#
#   ./deployment/scripts/bootstrap.sh
#
# Run it once per AWS account, with admin credentials (your own aws configure
# login, or CloudShell). It creates the things the main Terraform must NOT
# own, because a destroy would otherwise delete the very state and role the
# destroy is running with:
#
#   1. S3 bucket   <app>-tfstate-<account id>   Terraform state (versioned, private, encrypted)
#   2. DynamoDB    <app>-tf-locks               state locking
#   3. IAM OIDC provider for GitHub Actions     (skipped if it already exists)
#   4. IAM role    <app>-gha-deployer           what the workflows assume; no stored AWS keys
#
# It is safe to run again: existing pieces are left alone.
#
# Environment variables
#   GITHUB_REPO=owner/name   default: wasim0028/yt-viewer-tracker
#   GITHUB_ENV_NAME=name     GitHub Environment the workflows use (default: production)
#   GITHUB_OWNER_ID / GITHUB_REPO_ID   numeric ids (found automatically for public repos)
#   AWS_REGION=...           default: ap-south-1
#   APP_NAME=...             default: yt-viewer-tracker

set -euo pipefail

APP_NAME="${APP_NAME:-yt-viewer-tracker}"
GITHUB_REPO="${GITHUB_REPO:-wasim0028/yt-viewer-tracker}"
GITHUB_ENV_NAME="${GITHUB_ENV_NAME:-production}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
export AWS_REGION AWS_PAGER=""

command -v aws >/dev/null 2>&1 || { echo "aws CLI not installed (see README, Prerequisites)" >&2; exit 1; }
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" \
  || { echo "AWS CLI isn't signed in. Run 'aws configure' first." >&2; exit 1; }

BUCKET="${APP_NAME}-tfstate-${ACCOUNT}"
TABLE="${APP_NAME}-tf-locks"
ROLE="${APP_NAME}-gha-deployer"
OIDC_URL="token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT}:oidc-provider/${OIDC_URL}"

say() { printf '  %s\n' "$1"; }
echo "Account $ACCOUNT, region $AWS_REGION, repo $GITHUB_REPO"

# 1. State bucket ------------------------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  say "bucket $BUCKET exists"
else
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
  fi
  say "bucket $BUCKET created"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 2. Lock table --------------------------------------------------------------
if aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  say "lock table $TABLE exists"
else
  aws dynamodb create-table --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE"
  say "lock table $TABLE created"
fi

# 3. GitHub OIDC provider ----------------------------------------------------
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  say "OIDC provider exists"
else
  aws iam create-open-id-connect-provider --url "https://${OIDC_URL}" \
    --client-id-list sts.amazonaws.com >/dev/null
  say "OIDC provider created"
fi

# 4. Deployer role -----------------------------------------------------------
# Only jobs of THIS repo that run in the named GitHub Environment can assume it.
# GitHub now puts numeric IDs into the token subject
# (repo:owner@<owner id>/name@<repo id>:environment:x). Both forms are accepted.
# IDs come from GITHUB_OWNER_ID / GITHUB_REPO_ID, or from the GitHub API.
OWNER="${GITHUB_REPO%%/*}"; NAME="${GITHUB_REPO##*/}"
if [[ -z "${GITHUB_OWNER_ID:-}" || -z "${GITHUB_REPO_ID:-}" ]] \
   && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  J="$(curl -fsS "https://api.github.com/repos/${GITHUB_REPO}" 2>/dev/null || true)"
  GITHUB_OWNER_ID="$(printf '%s' "$J" | jq -r '.owner.id // empty' 2>/dev/null || true)"
  GITHUB_REPO_ID="$(printf '%s' "$J" | jq -r '.id // empty' 2>/dev/null || true)"
fi
SUBS="\"repo:${GITHUB_REPO}:environment:${GITHUB_ENV_NAME}\""
if [[ -n "${GITHUB_OWNER_ID:-}" && -n "${GITHUB_REPO_ID:-}" ]]; then
  SUBS="${SUBS}, \"repo:${OWNER}@${GITHUB_OWNER_ID}/${NAME}@${GITHUB_REPO_ID}:environment:${GITHUB_ENV_NAME}\""
  say "repo ids: owner ${GITHUB_OWNER_ID}, repo ${GITHUB_REPO_ID}"
else
  say "WARNING: could not look up the repo ids. If sign-in fails with 'Not authorized', re-run with"
  say "         GITHUB_OWNER_ID=<id> GITHUB_REPO_ID=<id> (the workflow's OIDC claims show them in the sub)."
fi
TRUST="$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${OIDC_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_URL}:aud": "sts.amazonaws.com",
        "${OIDC_URL}:sub": [ ${SUBS} ]
      }
    }
  }]
}
JSON
)"
if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document "$TRUST"
  aws iam update-role --role-name "$ROLE" --max-session-duration 10800 >/dev/null
  say "role $ROLE updated"
else
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document "$TRUST" \
    --max-session-duration 10800 >/dev/null
  say "role $ROLE created"
fi
# Terraform creates EKS, IAM roles, RDS, VPC... so the role needs broad rights.
aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"
cat <<MSG

Done. Now set these up in GitHub (repo -> Settings):

  1. Environments -> New environment -> name it:  ${GITHUB_ENV_NAME}
       (optional: add "Required reviewers" for an approval before every run,
        and limit "Deployment branches" to: devops)
  2. Secrets and variables -> Actions -> Variables -> New repository variable
       AWS_ROLE_ARN = ${ROLE_ARN}
  3. Environment "${GITHUB_ENV_NAME}" -> Environment secrets
       YOUTUBE_API_KEY = <your YouTube Data API v3 key>
       DB_PASSWORD     = <optional: your own RDS password; leave unset to have one generated>
  4. Settings -> Actions -> General -> Workflow permissions ->
       "Read and write permissions"  (so the workflows can commit image tags)

State bucket: ${BUCKET}
Lock table:   ${TABLE}
MSG
