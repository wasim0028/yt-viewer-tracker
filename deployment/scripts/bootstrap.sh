#!/usr/bin/env bash
#
# Bootstraps the entire yt-viewer-tracker cluster from scratch:
# Terraform apply -> kubectl config -> CoreDNS Fargate patch -> cluster
# add-ons (ESO, ALB Controller, ArgoCD) -> placeholder substitution ->
# ArgoCD Application.
#
# Idempotent: safe to re-run. Each step checks whether its work is already
# done before doing it again, rather than blindly re-applying everything.

set -euo pipefail
IFS=$'\n\t'

# ---- Configuration ----
AWS_REGION="${AWS_REGION:-ap-south-1}"
# Which folder under deployment/terraform/environments/ to deploy.
# To deploy another app or environment: TF_ENV=staging ./bootstrap.sh
TF_ENV="${TF_ENV:-production}"
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform/environments/${TF_ENV}" && pwd)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()   { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required command '$1' not found on PATH. Install it before continuing."
    exit 1
  fi
}

log "Checking required tools are installed"
for cmd in terraform aws kubectl helm jq kustomize; do
  require_command "$cmd"
done

# ---- Step 1: Terraform apply ----
log "Step 1/7: Terraform apply (VPC, EKS, RDS, ECR, Secrets Manager, IAM)"
(
  cd "$TERRAFORM_DIR"
  terraform init -input=false
  terraform apply -input=false -auto-approve
)

TF_OUTPUT="$(cd "$TERRAFORM_DIR" && terraform output -json)"
EXTERNAL_SECRETS_ROLE_ARN="$(echo "$TF_OUTPUT" | jq -r '.external_secrets_role_arn.value')"
GITHUB_ACTIONS_ROLE_ARN="$(echo "$TF_OUTPUT" | jq -r '.github_actions_role_arn.value')"
ADOT_COLLECTOR_ROLE_ARN="$(echo "$TF_OUTPUT" | jq -r '.adot_collector_role_arn.value')"
AMP_WORKSPACE_ENDPOINT="$(echo "$TF_OUTPUT" | jq -r '.amp_workspace_endpoint.value')"
ECR_BACKEND_URL="$(echo "$TF_OUTPUT" | jq -r '.ecr_backend_repository_url.value')"
ECR_FRONTEND_URL="$(echo "$TF_OUTPUT" | jq -r '.ecr_frontend_repository_url.value')"
LB_CONTROLLER_ROLE_ARN="$(echo "$TF_OUTPUT" | jq -r '.lb_controller_role_arn.value')"
CLUSTER_NAME="$(echo "$TF_OUTPUT" | jq -r '.eks_cluster_name.value')"
API_KEYS_SECRET_ID="$(echo "$TF_OUTPUT" | jq -r '.api_keys_secret_name.value')"
VPC_ID="$(echo "$TF_OUTPUT" | jq -r '.vpc_id.value')"

if [[ -z "$EXTERNAL_SECRETS_ROLE_ARN" || "$EXTERNAL_SECRETS_ROLE_ARN" == "null" ]]; then
  error "Could not read external_secrets_role_arn from Terraform output - did apply actually succeed?"
  exit 1
fi

# ---- Step 2: Point kubectl at the new cluster ----
log "Step 2/7: Configuring kubectl"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# ---- Step 3: Patch CoreDNS to run on Fargate ----
# Without this, CoreDNS has nowhere to schedule at all on a cluster with no
# EC2 node groups - in-cluster DNS resolution breaks entirely, and every
# other step below (which relies on Service name resolution) fails in
# confusing ways. This is not optional polish; it's a documented,
# necessary step for any Fargate-only EKS cluster.
log "Step 3/7: Patching CoreDNS to schedule on Fargate"
if kubectl get deployment coredns -n kube-system \
    -o jsonpath='{.spec.template.metadata.annotations.eks\.amazonaws\.com/compute-type}' 2>/dev/null | grep -q "ec2"; then
  kubectl patch deployment coredns -n kube-system --type json \
    -p '[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
  kubectl rollout restart deployment coredns -n kube-system
  kubectl rollout status deployment coredns -n kube-system --timeout=300s
else
  echo "CoreDNS already patched for Fargate - skipping"
fi

# ---- Step 4: Set the real external API keys in Secrets Manager ----
log "Step 4/7: External API keys in Secrets Manager"
CURRENT_VALUE="$(aws secretsmanager get-secret-value --secret-id "$API_KEYS_SECRET_ID" --query SecretString --output text)"
if echo "$CURRENT_VALUE" | jq -e '.YOUTUBE_API_KEY | test("REPLACE_ME")' >/dev/null 2>&1; then
  echo "YOUTUBE_API_KEY is still a placeholder."
  read -rsp "Enter your real YouTube Data API v3 key (input hidden): " YT_KEY
  echo ""
  read -rsp "Enter your ad-network API key, or press Enter to leave as placeholder: " ADS_KEY
  echo ""
  ADS_KEY="${ADS_KEY:-REPLACE_ME_VIA_AWS_CLI_NOT_TERRAFORM}"
  NEW_VALUE="$(jq -n --arg yt "$YT_KEY" --arg ads "$ADS_KEY" '{YOUTUBE_API_KEY: $yt, ADS_API_KEY: $ads}')"
  aws secretsmanager put-secret-value --secret-id "$API_KEYS_SECRET_ID" --secret-string "$NEW_VALUE"
else
  echo "Real API keys already set - skipping (re-run with --force-secrets to override, not implemented here on purpose, do it via the console/CLI directly if truly needed)"
fi

# ---- Step 5: Install cluster add-ons ----
log "Step 5/7: Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --wait

log "Step 5/7: Installing AWS Load Balancer Controller"
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${LB_CONTROLLER_ROLE_ARN}" \
  --wait

log "Step 5/7: Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment argocd-server -n argocd --timeout=180s

# ---- Step 6: Substitute placeholders into the manifest files ----
log "Step 6/7: Filling in real ARNs and ECR URLs"
sed -i.bak "s#REPLACE_WITH_TERRAFORM_OUTPUT_external_secrets_role_arn#${EXTERNAL_SECRETS_ROLE_ARN}#" \
  "$REPO_ROOT/deployment/k8s/base/external-secrets-sa.yaml"
sed -i.bak "s#REPLACE_WITH_TERRAFORM_OUTPUT_adot_collector_role_arn#${ADOT_COLLECTOR_ROLE_ARN}#" \
  "$REPO_ROOT/deployment/k8s/base/adot-collector.yaml"
sed -i.bak "s#REPLACE_WITH_TERRAFORM_OUTPUT_amp_workspace_endpoint_api_v1_remote_write#${AMP_WORKSPACE_ENDPOINT}api/v1/remote_write#" \
  "$REPO_ROOT/deployment/k8s/base/adot-collector.yaml"
sed -i.bak "s#REPLACE_WITH_TERRAFORM_OUTPUT_github_actions_role_arn#${GITHUB_ACTIONS_ROLE_ARN}#" \
  "$REPO_ROOT/.github/workflows/deploy.yaml"
(
  cd "$REPO_ROOT/deployment/k8s/base"
  kustomize edit set image "backend-image=${ECR_BACKEND_URL}:latest" "frontend-image=${ECR_FRONTEND_URL}:latest"
)
find "$REPO_ROOT" -name "*.bak" -delete

# ---- Step 7: Apply the ArgoCD Application ----
log "Step 7/7: Applying the ArgoCD Application"
kubectl apply -f "$REPO_ROOT/argocd/application.yaml"

log "Bootstrap complete."
cat <<EOF

Next steps:
  1. Commit and push the filled-in placeholder files - ArgoCD/CI both need
     these committed, not just present on this machine.
  2. Push to 'main' to trigger the first real image build via GitHub Actions.
  3. Get the ArgoCD initial admin password:
       kubectl -n argocd get secret argocd-initial-admin-secret \\
         -o jsonpath='{.data.password}' | base64 -d
  4. Get the Ingress's public address once the ALB provisions (may take a
     few minutes):
       kubectl get ingress -n yt-viewer-tracker
EOF
