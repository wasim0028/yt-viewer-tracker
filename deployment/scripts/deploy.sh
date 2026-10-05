#!/usr/bin/env bash
#
# deploy.sh - one entry point for every deployment task.
#
#   ./deployment/scripts/deploy.sh <command>
#
# EKS (production scale)
#   all          Everything below, in order (first bring-up)
#   init         terraform init
#   plan         terraform plan
#   apply        terraform apply
#   addons       kubectl access, CoreDNS on Fargate, External Secrets,
#                AWS Load Balancer Controller, ArgoCD
#   secrets      Put your YouTube API key into Secrets Manager
#   configure    Write AWS role ARNs into the Kubernetes manifests,
#                set (or print) the GitHub Actions variables
#   build        Build both Docker images, tagged with the git commit
#   push         Push them to ECR and point kustomization.yaml at them
#   argocd       Apply argocd/root-app.yaml (app of apps)
#   status       ArgoCD apps, pods, secrets, and the site URL
#   destroy      Delete the load balancer first, empty ECR, then terraform destroy
#
# Environment variables
#   AUTO_APPROVE=1          Skip Terraform's "yes" prompt on apply
#   TF_VAR_db_password=...  Your own RDS password (optional; generated if unset)
#   YOUTUBE_API_KEY=...     Skip the key prompt in 'secrets'

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/deployment/terrafrom"
K8S_DIR="$REPO_ROOT/deployment/k8s/base"
APP_NAMESPACE="${APP_NAMESPACE:-yt-viewer-tracker}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()     { printf '%b[%s] ✓ %s%b\n' "$GREEN" "$(date +%H:%M:%S)" "$1" "$NC"; }
warn()    { printf '%b[%s] ⚠ %s%b\n' "$YELLOW" "$(date +%H:%M:%S)" "$1" "$NC"; }
error()   { printf '%b[%s] ✗ %s%b\n' "$RED" "$(date +%H:%M:%S)" "$1" "$NC" >&2; exit 1; }
section() { printf '\n%b══════════════════════════════════════════════\n  %s\n══════════════════════════════════════════════%b\n' "$CYAN" "$1" "$NC"; }

require() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || error "'$c' is not installed or not on PATH (see README, Prerequisites)."
  done
}

# Reads a simple string value from <dir>/terraform.tfvars
tfvar() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1/terraform.tfvars" | head -n 1
}

[[ -d "$TF_DIR" ]] || error "No Terraform folder at $TF_DIR."
AWS_REGION="${AWS_REGION:-$(tfvar "$TF_DIR" aws_region)}"
export AWS_REGION

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

tf_init() {
  require aws terraform
  section "Terraform init"
  aws sts get-caller-identity >/dev/null 2>&1 || error "AWS CLI isn't signed in. Run 'aws configure' first."
  # provider.tf has no backend block, so state is kept locally in deployment/terrafrom.
  terraform -chdir="$TF_DIR" init -input=false
}

tf_plan() {
  tf_init
  section "Terraform plan"
  terraform -chdir="$TF_DIR" plan -input=false
}

tf_apply() {
  tf_init
  section "Terraform apply (EKS takes 15-20 minutes; don't interrupt it)"
  if [[ "${AUTO_APPROVE:-}" == "1" ]]; then
    terraform -chdir="$TF_DIR" apply -input=false -auto-approve
  else
    terraform -chdir="$TF_DIR" apply
  fi
}

# ---------------------------------------------------------------------------
# Cluster add-ons
# ---------------------------------------------------------------------------

setup_kubectl() {
  require kubectl
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$(tf_out eks_cluster_name)" >/dev/null
  log "kubectl points at $(tf_out eks_cluster_name)"
}

patch_coredns() {
  # On a cluster with no EC2 nodes, CoreDNS is created pinned to EC2 and can
  # never start. Removing that annotation lets it run on Fargate.
  if kubectl get deployment coredns -n kube-system \
      -o jsonpath='{.spec.template.metadata.annotations.eks\.amazonaws\.com/compute-type}' 2>/dev/null | grep -q ec2; then
    kubectl patch deployment coredns -n kube-system --type json \
      -p '[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
    kubectl rollout restart deployment coredns -n kube-system
  fi
  kubectl rollout status deployment coredns -n kube-system --timeout=300s
  log "CoreDNS running on Fargate"
}

install_addons() {
  require aws terraform kubectl helm
  section "Cluster add-ons"
  setup_kubectl
  patch_coredns

  helm repo add external-secrets https://charts.external-secrets.io --force-update >/dev/null
  helm repo add eks https://aws.github.io/eks-charts --force-update >/dev/null

  helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace --wait --timeout 10m
  log "External Secrets Operator installed"

  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$(tf_out eks_cluster_name)" \
    --set region="$AWS_REGION" \
    --set vpcId="$(tf_out vpc_id)" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=$(tf_out lb_controller_role_arn)" \
    --wait --timeout 10m
  log "AWS Load Balancer Controller installed"

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  # --server-side avoids "metadata.annotations: Too long" on ArgoCD's large CRDs.
  kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null
  kubectl rollout status deployment argocd-server -n argocd --timeout=600s
  log "ArgoCD installed"
}

# ---------------------------------------------------------------------------
# Secrets and configuration
# ---------------------------------------------------------------------------

set_api_keys() {
  require aws terraform jq
  section "YouTube API key -> Secrets Manager"
  local secret_id current key value
  secret_id="$(tf_out api_keys_secret_name)"
  current="$(aws secretsmanager get-secret-value --secret-id "$secret_id" --query SecretString --output text)"
  if ! echo "$current" | jq -e '.YOUTUBE_API_KEY | test("REPLACE_ME")' >/dev/null; then
    log "Real API key already set in $secret_id (change it: aws secretsmanager put-secret-value)"
    return
  fi
  key="${YOUTUBE_API_KEY:-}"
  if [[ -z "$key" ]]; then
    read -rsp "YouTube Data API v3 key (input hidden): " key; echo
  fi
  [[ -n "$key" ]] || error "No key entered."
  value="$(echo "$current" | jq --arg k "$key" '.YOUTUBE_API_KEY = $k')"
  aws secretsmanager put-secret-value --secret-id "$secret_id" --secret-string "$value" >/dev/null
  log "Saved to $secret_id"
}

configure_manifests() {
  require terraform
  section "Writing AWS identifiers into the manifests"
  local eso_role adot_role amp
  eso_role="$(tf_out external_secrets_role_arn)"
  adot_role="$(tf_out adot_collector_role_arn)"
  amp="$(tf_out amp_workspace_endpoint)"

  # Replace the values (not just the placeholders), so re-running after a
  # rebuild with new ARNs updates them.
  sed -i.bak -E "s#(eks\.amazonaws\.com/role-arn:).*#\1 \"${eso_role}\"#" "$K8S_DIR/external-secrets-sa.yaml"
  sed -i.bak -E \
    -e "s#(eks\.amazonaws\.com/role-arn:).*#\1 \"${adot_role}\"#" \
    -e "s#(endpoint:).*#\1 \"${amp}api/v1/remote_write\"#" \
    "$K8S_DIR/adot-collector.yaml"
  rm -f "$K8S_DIR"/*.bak
  log "Updated external-secrets-sa.yaml and adot-collector.yaml"

  local -a names=(AWS_ECR_PUSH_ROLE_ARN AWS_TERRAFORM_PLAN_ROLE_ARN AWS_TERRAFORM_APPLY_ROLE_ARN TF_STATE_BUCKET)
  local -a values=(
    "$(tf_out github_actions_role_arn)"
    "$(tf_out github_terraform_plan_role_arn)"
    "$(tf_out github_terraform_apply_role_arn)"
    "$(tf_out tf_state_bucket)"
  )
  local i
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    for i in "${!names[@]}"; do
      (cd "$REPO_ROOT" && gh variable set "${names[$i]}" --body "${values[$i]}" >/dev/null)
    done
    log "GitHub Actions variables set with the gh CLI"
  else
    warn "Set these in GitHub -> Settings -> Secrets and variables -> Actions -> Variables:"
    for i in "${!names[@]}"; do
      printf '    %-30s %s\n' "${names[$i]}" "${values[$i]}"
    done
  fi
}

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

image_tag() { git -C "$REPO_ROOT" rev-parse --short=12 HEAD; }

build_images() {
  require docker git terraform
  section "Building images"
  local tag; tag="$(image_tag)"
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- backend frontend deployment/docker)" ]]; then
    warn "Uncommitted changes in backend/, frontend/ or deployment/docker/: images tagged $tag won't match that commit."
  fi
  docker build -f "$REPO_ROOT/deployment/docker/Dockerfile.backend" \
    -t "$(tf_out ecr_backend_repository_url):$tag" "$REPO_ROOT"
  docker build -f "$REPO_ROOT/deployment/docker/Dockerfile.frontend" \
    -t "$(tf_out ecr_frontend_repository_url):$tag" "$REPO_ROOT"
  log "Built backend and frontend, tag $tag"
}

push_images() {
  require docker git terraform aws kustomize
  section "Pushing images to ECR"
  local tag backend frontend registry url repo
  tag="$(image_tag)"
  backend="$(tf_out ecr_backend_repository_url)"
  frontend="$(tf_out ecr_frontend_repository_url)"
  registry="${backend%%/*}"
  aws ecr get-login-password | docker login --username AWS --password-stdin "$registry" >/dev/null

  for url in "$backend" "$frontend"; do
    repo="${url#*/}"
    if aws ecr describe-images --repository-name "$repo" --image-ids "imageTag=$tag" >/dev/null 2>&1; then
      log "$repo:$tag already in ECR, skipping (tags are immutable)"
    else
      docker push "$url:$tag"
      log "Pushed $repo:$tag"
    fi
  done

  (cd "$K8S_DIR" && kustomize edit set image "backend-image=$backend:$tag" "frontend-image=$frontend:$tag")
  log "kustomization.yaml now points at tag $tag"
  warn "Commit and push deployment/k8s/base/kustomization.yaml to main. ArgoCD deploys what's in git."
}

# ---------------------------------------------------------------------------
# ArgoCD, status
# ---------------------------------------------------------------------------

argocd_apply() {
  require kubectl
  section "ArgoCD root application"
  kubectl apply -f "$REPO_ROOT/argocd/root-app.yaml"
  kubectl get applications -n argocd
}

status() {
  require kubectl terraform aws
  setup_kubectl
  section "ArgoCD applications"
  kubectl get applications -n argocd 2>/dev/null || warn "ArgoCD not installed yet"
  section "Pods ($APP_NAMESPACE)"
  kubectl get pods -n "$APP_NAMESPACE" 2>/dev/null || warn "Namespace not created yet"
  section "Secrets sync"
  kubectl get externalsecret -n "$APP_NAMESPACE" 2>/dev/null || true
  section "Site"
  local host
  host="$(kubectl get ingress -n "$APP_NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "$host" ]]; then log "http://$host"; else warn "No load balancer address yet (takes 3-5 minutes after the Ingress appears)"; fi
}

# ---------------------------------------------------------------------------
# Destroy
# ---------------------------------------------------------------------------

pre_destroy_cleanup() {
  section "Pre-destroy cleanup"
  local cluster arns i url repo ids
  cluster="$(tf_out eks_cluster_name 2>/dev/null || true)"

  if [[ -n "$cluster" ]] && aws eks describe-cluster --name "$cluster" >/dev/null 2>&1; then
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$cluster" >/dev/null
    # The load balancer was created by the controller, not Terraform. While it
    # exists, Terraform can't delete the VPC and destroy hangs.
    kubectl delete -f "$REPO_ROOT/argocd/root-app.yaml" --ignore-not-found --timeout=300s || warn "Couldn't delete ArgoCD apps; continuing"
    kubectl delete ingress --all -n "$APP_NAMESPACE" --ignore-not-found --timeout=300s || true

    for i in $(seq 1 30); do
      arns="$(aws resourcegroupstaggingapi get-resources \
        --resource-type-filters elasticloadbalancing:loadbalancer \
        --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$cluster" \
        --query 'ResourceTagMappingList[].ResourceARN' --output text)"
      [[ -z "$arns" || "$arns" == "None" ]] && { log "Load balancer gone"; break; }
      [[ $i -eq 30 ]] && error "Load balancer still exists after 5 minutes: $arns"
      sleep 10
    done
  fi

  # Terraform won't delete ECR repositories that still contain images.
  for url in "$(tf_out ecr_backend_repository_url 2>/dev/null || true)" "$(tf_out ecr_frontend_repository_url 2>/dev/null || true)"; do
    [[ -n "$url" ]] || continue
    repo="${url#*/}"
    ids="$(aws ecr list-images --repository-name "$repo" --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')"
    if [[ "$ids" != "[]" ]]; then
      aws ecr batch-delete-image --repository-name "$repo" --image-ids "$ids" >/dev/null
      log "Emptied $repo"
    fi
  done
}

tf_destroy() {
  require aws terraform kubectl
  warn "This deletes the EKS cluster, the database (a final snapshot is kept), and everything else this Terraform created."
  local answer
  read -rp "Type 'destroy' to continue: " answer
  [[ "$answer" == "destroy" ]] || error "Cancelled."
  tf_init
  pre_destroy_cleanup
  section "Terraform destroy"
  terraform -chdir="$TF_DIR" destroy -input=false -auto-approve
  log "Destroyed. Secrets Manager keeps the deleted secrets for 7 days; redeploying sooner fails until you restore them."
}

# ---------------------------------------------------------------------------

all() {
  tf_apply
  install_addons
  set_api_keys
  configure_manifests
  build_images
  push_images
  argocd_apply
  section "Done. One step left"
  cat << EOF
ArgoCD deploys what's in git, so commit what this run changed:

  git add deployment/k8s/base
  git commit -m "Configure AWS identifiers and first image tags"
  git push origin main

Then follow progress with:  ./deployment/scripts/deploy.sh status
EOF
}

usage() { awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "${BASH_SOURCE[0]}"; }

case "${1:-}" in
  all)         all ;;
  init)        tf_init ;;
  plan)        tf_plan ;;
  apply)       tf_apply ;;
  addons)      install_addons ;;
  secrets)     set_api_keys ;;
  configure)   configure_manifests ;;
  build)       build_images ;;
  push)        push_images ;;
  argocd)      argocd_apply ;;
  status)      status ;;
  destroy)     tf_destroy ;;
  ""|-h|--help|help) usage ;;
  *) usage; error "Unknown command: $1" ;;
esac
