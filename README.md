![Viewer Watch](banner.svg)

# Viewer Watch

**Live YouTube viewer tracking, channel vs. channel, in real time.**

## About

Viewer Watch compares the live audience of YouTube channels head-to-head.
Every 3 minutes it asks the YouTube Data API how many people are watching
each live stream a channel is running, adds them up per channel, and stores
the reading in PostgreSQL. The dashboard shows a live chart, a reading log,
and history for any date range.

**Features**

- Live comparison chart, refreshed every 30 seconds (1H / 6H / 24H / 3D windows)
- Viewers are summed across **every** live stream a channel is running
- Automatic stream discovery: new streams are picked up, ended ones dropped
- History view with raw, hourly, or daily resolution
- Light and dark mode, responsive layout
- Rotating ad slots on wide screens (images from `backend/public/ads/`)
- Quota-friendly: up to 50 videos are checked in a single API call

**Tech stack**

| Layer | Technology |
|---|---|
| Frontend | React 18, Vite, Recharts, served by nginx |
| Backend | Node.js 22, Express, `pg`, `prom-client` |
| Database | PostgreSQL 16 (AWS RDS in production) |
| Containers | Docker (multi-stage, non-root images) |
| Orchestration | AWS EKS on Fargate (no servers to manage) |
| Infrastructure | Terraform |
| Delivery | ArgoCD (GitOps), `deploy.sh` for builds and bring-up |
| Secrets | AWS Secrets Manager + External Secrets Operator |
| Monitoring | CloudWatch Logs, Amazon Managed Prometheus (via ADOT Collector) |

**Three ways to run it**

| | Where | Database | Section |
|---|---|---|---|
| 1 | Your computer, for development | Docker PostgreSQL | [Run locally](#1-run-locally-development) |
| 2 | Any server, including one EC2 instance | An existing PostgreSQL / RDS | [Docker Compose](#2-run-with-docker-compose-existing-postgresql--rds) |
| 3 | AWS EKS (Fargate) | RDS created by Terraform | [Deploy to EKS](#3-deploy-to-aws-eks-terraform--argocd), by hand or with [one click from GitHub Actions](#4-one-click-deploy-and-cicd-github-actions) |

---

## Architecture (EKS deployment)

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  Internet                                                            │
│     │                                                                │
│     ▼                                                                │
│  AWS Application Load Balancer  (created by the AWS Load Balancer    │
│     │                            Controller from ingress.yaml)       │
│     ▼                                                                │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  EKS cluster "yt-viewer-tracker" on Fargate (ap-south-1)       │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │ Namespace: yt-viewer-tracker                             │  │  │
│  │  │  [frontend x2]  nginx + React, runs as uid 101           │  │  │
│  │  │       │  /api/*  /ads-media/*  →  backend:4000           │  │  │
│  │  │  [backend x1]   Node.js API + YouTube poller             │  │  │
│  │  │  [adot-collector]  scrapes /metrics → Managed Prometheus │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │  argocd            watches this repo (branch devops), auto-sync│  │
│  │  external-secrets  Secrets Manager → Kubernetes Secret         │  │
│  │  kube-system       AWS Load Balancer Controller, CoreDNS       │  │
│  └─────────────────────────────┬──────────────────────────────────┘  │
│                                ▼                                     │
│  RDS PostgreSQL 16  (private subnets, encrypted, 7-day backups)      │
│                                                                      │
│  ECR            yt-viewer-tracker-backend, yt-viewer-tracker-frontend│
│  Secrets Mgr    yt-viewer-tracker/database-url, .../api-keys         │
│  Logs/Metrics   CloudWatch (Fargate Fluent Bit), Managed Prometheus  │
│                                                                      │
│  deploy.sh build + push → ECR → commit new image tag → ArgoCD syncs  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Project structure

```
.
├── backend/                       Node.js API + YouTube poller
│   ├── server.js                  /api/*, /ads-media, /healthz, /metrics
│   ├── poller.js                  polling, stream discovery, summing
│   ├── youtube.js                 YouTube Data API calls
│   ├── db.js                      PostgreSQL access
│   ├── ads.js, ads.json           ad creatives for the side rails
│   ├── config.json                channels to track
│   ├── .env.example               every setting, with comments
│   └── public/ads/                ad images
├── frontend/                      React + Vite dashboard
│   └── src/components/            Navbar, LiveView, HistoryView, ChartPanel, ...
├── argocd/
│   ├── root-app.yaml              "app of apps", applied once
│   └── apps/yt-viewer-tracker.yaml
├── .github/workflows/             deploy.yml, destroy.yml, release.yml (GitHub Actions)
├── .gitignore                     keeps Terraform state, .env, node_modules out of git
└── deployment/
    ├── docker/
    │   ├── Dockerfile.backend     multi-stage, runs as non-root "node"
    │   ├── Dockerfile.frontend    multi-stage, nginx as uid 101
    │   ├── nginx.conf             proxies /api/ and /ads-media/ → backend:4000
    │   └── docker-compose.yaml    backend + frontend, bring your own database
    ├── k8s/base/                  Kubernetes manifests (Kustomize)
    ├── scripts/deploy.sh          every deployment task, one entry point
    ├── scripts/bootstrap.sh       one-time: state bucket, lock table, CI role
    └── terrafrom/                 Terraform
        ├── main.tf                connects the modules
        ├── provider.tf            providers, S3 backend
        ├── variables.tf, terraform.tfvars, output.tf
        ├── modules/               vpc, eks-fargate, rds-postgres, ecr,
        │                          app-secrets, irsa-role, github-oidc, prometheus
        └── policies/              official AWS Load Balancer Controller IAM policy
```

---

## Get a YouTube API key

1. [Google Cloud Console](https://console.cloud.google.com/) → create or select a project
2. **APIs & Services → Library** → **YouTube Data API v3** → **Enable**
3. **APIs & Services → Credentials → Create credentials → API key**
4. Restrict the key to **YouTube Data API v3**

It's free: 10,000 quota units per project per day, reset at midnight Pacific.

> **Never commit the key.** If a key ever lands in a commit, regenerate it.
> Deleting the line doesn't remove it from git history.

### Channels to track

Edit `backend/config.json`:

```json
{ "name": "RBANGLA", "color": "#E5384B", "channelId": "UCajVjEHDoVn_AHsunUZz_EQ",
  "videoIds": ["YoAzEs1GwJg"], "autoDiscover": true }
```

- `channelId`: channel page → **About → Share channel → Copy channel ID**
- `videoIds`: optional pinned live streams (the `v=` part of the URL). Checking them costs almost nothing.
- `autoDiscover`: finds the channel's other live streams automatically (100 quota units per search).

---

## 1. Run locally (development)

Needs Node.js 22 and Docker (for PostgreSQL).

```bash
# PostgreSQL
docker run -d --name yt-postgres -e POSTGRES_PASSWORD=devpassword \
  -e POSTGRES_DB=yt_viewer_tracker -p 5432:5432 postgres:16

# Backend (terminal 1)
cd backend
npm install
cp .env.example .env
# edit .env:
#   YOUTUBE_API_KEY=your-key
#   DATABASE_URL=postgres://postgres:devpassword@localhost:5432/yt_viewer_tracker
#   PGSSL=false
npm start

# Frontend (terminal 2)
cd frontend
npm install
npm run dev          # http://localhost:5173
```

The backend creates its own table on first start. You should see
`[db] connected to PostgreSQL, schema ready`. Log timestamps are UTC; the
dashboard shows local time. In development, Vite forwards `/api` and
`/ads-media` to the backend on port 4000.

---

## 2. Run with Docker Compose (existing PostgreSQL / RDS)

`deployment/docker/docker-compose.yaml` runs the **backend and the frontend**.
It does not start a database: you bring your own PostgreSQL, such as an RDS
instance you already have.

```bash
cd deployment/docker
export DATABASE_URL='postgres://USER:PASSWORD@YOUR-RDS-ENDPOINT:5432/YOUR_DB_NAME'
export YOUTUBE_API_KEY='your-key'
docker compose up -d --build
```

PowerShell:

```powershell
cd deployment\docker
$env:DATABASE_URL = 'postgres://USER:PASSWORD@YOUR-RDS-ENDPOINT:5432/YOUR_DB_NAME'
$env:YOUTUBE_API_KEY = 'your-key'
docker compose up -d --build
```

Then open **http://localhost:8080** (or `http://<server-ip>:8080`) and check:

```bash
docker compose ps                    # both running, backend "(healthy)"
docker compose logs -f backend       # want: [db] connected to PostgreSQL, schema ready
curl localhost:8080/health           # healthy
curl localhost:8080/api/channels     # your channels as JSON
```

Stop with `docker compose down`. Your database is not touched.

Rules for the database:

- It must be **PostgreSQL**, and the database named at the end of the URL must already exist (the app creates its table, not the database).
- **URL-encode special characters in the password:** `#` → `%23`, `@` → `%40`, `!` → `%21`.
- `PGSSL` defaults to `true` (RDS expects SSL). For a database without SSL, `export PGSSL=false`.
- The server running Docker must be able to reach the database on port 5432 (see below).

### On an EC2 instance

Size: **t3.small** (2 GB) is enough to run the app; the backend uses about
80 MB. Use **t3.medium** (4 GB) if the same instance also runs `deploy.sh`.
Use an Intel/AMD type (not ARM) if you will build images for EKS.

Amazon Linux 2023:

```bash
sudo dnf install -y docker git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"          # then log out and back in

# Compose and Buildx plugins (the Dockerfiles need BuildKit)
ARCH="$(uname -m)"; BX="$([ "$ARCH" = x86_64 ] && echo amd64 || echo arm64)"
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$ARCH" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo curl -fsSL "https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-$BX" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
sudo chmod +x /usr/local/lib/docker/cli-plugins/*

git clone -b devops https://github.com/wasim0028/yt-viewer-tracker.git    # the branch with the deployment code
cd yt-viewer-tracker/deployment/docker
```

Then follow the Compose steps above. Also:

- **Security group (instance):** port **22** from your own IP only, and port **8080** for the app.
- **Security group (RDS):** allow **PostgreSQL 5432** from the instance's security group. Keep both in the same VPC. If the instance is outside the VPC, the database needs *Publicly accessible* turned on, and an inbound rule for the instance's IP.

---

## 3. Deploy to AWS EKS (Terraform + ArgoCD)

Everything goes through one script: `deployment/scripts/deploy.sh`. Run it
with no arguments for the command list.

### What gets created

| Resource | Purpose |
|---|---|
| VPC | 3 public + 3 private subnets across 3 AZs, 1 NAT gateway |
| EKS cluster on Fargate | No EC2 nodes to patch; one Fargate profile per namespace |
| RDS PostgreSQL 16 | Private, encrypted, 7-day backups, password generated for you |
| 2 ECR repositories | `yt-viewer-tracker-backend` and `-frontend`, immutable tags, last 10 images kept |
| 2 Secrets Manager secrets | `yt-viewer-tracker/database-url` (automatic) and `.../api-keys` (you fill in) |
| IAM roles | External Secrets, ADOT collector, Load Balancer Controller, GitHub OIDC |
| Amazon Managed Prometheus | Metrics storage |
| S3 bucket + DynamoDB table | Terraform state and locking; created once by `bootstrap.sh`, outside this stack |

> **Cost:** this runs around the clock. See [Cost estimate](#cost-estimate),
> and [Teardown](#teardown) to remove everything.

### Prerequisites

Linux, macOS, or **WSL on Windows**: `deploy.sh` is Bash and won't run in
PowerShell. `deploy.sh` checks for every tool before it changes anything.

```bash
# 1. AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install

# 2. Terraform >= 1.6
wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
unzip terraform_1.7.0_linux_amd64.zip && sudo mv terraform /usr/local/bin/

# 3. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 4. Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 5. sudo wget https://raw.githubusercontent.com/lerndevops/labs/master/scripts/installDocker.sh -P /tmp
sudo chmod 755 /tmp/installDocker.sh
sudo bash /tmp/installDocker.sh
sudo sh && sudo usermod -aG docker "$USER"   # then log out and back in

# 6. kustomize (standalone binary, NOT snap: snap's sandbox blocks access to
#    paths outside $HOME and fails with confusing "permission denied" errors)
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# 7. ArgoCD CLI (optional, for troubleshooting)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# 8. jq and git
sudo apt-get install -y jq git          # or: sudo dnf install -y jq git
```

Running by hand from your own machine is optional: the
[GitHub Actions workflows](#4-one-click-deploy-and-cicd-github-actions) install
Terraform, kubectl, Helm and kustomize themselves and run the same commands.

### Step-by-step

**Step 1: AWS credentials.**

```bash
aws configure                        # region: ap-south-1
aws sts get-caller-identity          # confirm which account you're deploying into
```

Terraform creates IAM roles, EKS, and RDS, so the user needs broad
permissions. For the first deploy, `AdministratorAccess` is simplest. On an
EC2 instance, attach an IAM role instead of using access keys.

**Step 2: Choose the branch ArgoCD watches.** The deployable code is on the
`devops` branch of `github.com/wasim0028/yt-viewer-tracker` (`main` holds the
application only). ArgoCD deploys whatever is committed on the branch named in
`targetRevision`, so in **both** `argocd/root-app.yaml` and
`argocd/apps/yt-viewer-tracker.yaml` set:

```yaml
targetRevision: devops
```

Commit and push that change before Step 10. To use another repo or branch,
change `repoURL` and `targetRevision` in the same two files. The repository
must be public, or you must register credentials for it in ArgoCD.

**Step 3: (Optional) choose your own database password.**

```bash
read -rsp "RDS password: " TF_VAR_db_password; echo
export TF_VAR_db_password
```

Skip this and Terraform generates a strong one. Rules (RDS's own): 8–128
characters, no `/`, `@`, `"`, or spaces. `read -s` keeps it out of your shell
history. If you set one, **set it on every Terraform run**: a run without it
switches the database to a generated password.

**Step 3b: Create the remote state (once per AWS account). Required before Step 5.**

```bash
bash deployment/scripts/bootstrap.sh
```

Creates the S3 bucket and lock table that hold Terraform state, plus the role GitHub Actions uses (see [section 4](#4-one-click-deploy-and-cicd-github-actions)). Safe to re-run. Until it has run, `deploy.sh init` stops with `State bucket '...' not found`.

> **Already have a local `terraform.tfstate` from an earlier deploy?** If that stack still exists in AWS, move its state into S3 before anything else: from `deployment/terrafrom` run `terraform init -migrate-state -reconfigure` with the same `-backend-config` values `deploy.sh init` uses (bucket `yt-viewer-tracker-tfstate-<account id>`, key `yt-viewer-tracker/terraform.tfstate`, your region, table `yt-viewer-tracker-tf-locks`, `encrypt=true`) and answer `yes`. Skipping this makes Terraform see an empty state and try to create everything again. If the old stack is already destroyed, just delete the local `terraform.tfstate*` files.

**Step 4: Check the settings** in `deployment/terrafrom/terraform.tfvars`:

| Setting | Value |
|---|---|
| `aws_region` | `ap-south-1` |
| `app_namespace` | `yt-viewer-tracker` |
| `ecr_repositories` | `["backend", "frontend"]` |
| `db_name`, `db_username` | `yt_viewer_tracker`, `yt_viewer_admin` |
| `api_key_names` | `["YOUTUBE_API_KEY", "ADS_API_KEY"]` |
| `github_repo` | `wasim0028/yt-viewer-tracker` |

The region `ap-south-1` is also set in `provider.tf` and in three Kubernetes
files (`cluster-secret-store.yaml`, `aws-logging-configmap.yaml`,
`adot-collector.yaml`). Change all of them together.

**Step 5: Terraform.**

```bash
./deployment/scripts/deploy.sh init
./deployment/scripts/deploy.sh plan      # read it: on a fresh account everything is "to add"
./deployment/scripts/deploy.sh apply     # type "yes"
```

`apply` takes roughly 15–25 minutes, mostly EKS and RDS. **Let it finish.**
Interrupting it can leave resources half-created.

**Step 6: Cluster add-ons.**

```bash
./deployment/scripts/deploy.sh addons
```

Points `kubectl` at the cluster, lets CoreDNS run on Fargate (without this,
in-cluster DNS never works on a cluster with no EC2 nodes), and installs
External Secrets Operator, the AWS Load Balancer Controller (with its IAM role
and the VPC ID, which Fargate can't discover on its own), and ArgoCD.

Fargate pods take **1–2 minutes** to start, so this step waits. **Run it before
Step 10:** it installs the ArgoCD custom resources that Step 10 needs. Check:

```bash
kubectl get crd | grep argoproj          # expect 3 lines (applications, applicationsets, appprojects)
kubectl get pods -A                      # everything Running
```

If it stops with `deployment "coredns" exceeded its progress deadline`, the
CoreDNS pods were created before the Fargate profile existed and stay
`Pending`. Restart them, then re-run `addons`:

```bash
kubectl patch deployment coredns -n kube-system --type merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"eks.amazonaws.com/compute-type":"fargate"}}}}}'
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system --timeout=600s
./deployment/scripts/deploy.sh addons
```

**Step 7: Your YouTube API key.**

```bash
./deployment/scripts/deploy.sh secrets
```

Prompts for the key (hidden) and saves it to Secrets Manager. Terraform never
sees or overwrites it. Set `YOUTUBE_API_KEY` in the environment to skip the prompt.

**Step 8: Write AWS identifiers into the manifests.**

```bash
./deployment/scripts/deploy.sh configure
```

Writes the IAM role ARNs and the Prometheus endpoint into
`deployment/k8s/base/`.

**Step 9: Build and push the first images.**

```bash
git add -A && git commit -m "Configure AWS identifiers"    # tags use the commit ID
./deployment/scripts/deploy.sh build
./deployment/scripts/deploy.sh push
```

Images are tagged with the 12-character git commit ID. `push` points
`deployment/k8s/base/kustomization.yaml` at them.

**Step 10: Register the app with ArgoCD.** Needs Step 6 done and `targetRevision`
pushed (Step 2).

```bash
./deployment/scripts/deploy.sh argocd
```

`no matches for kind "Application"` means the ArgoCD CRDs are missing: run
`deploy.sh addons` first.

**Step 11: Commit what the script changed** (on the `devops` branch). ArgoCD
deploys **what is in git**, not what is on your machine. Until you push, pods show
`ImagePullBackOff` or `InvalidImageName`. That is expected here, not a bug.

```bash
git add deployment/k8s/base
git commit -m "Set image tags and AWS identifiers"
git push origin devops
```

**Step 12: Get the URL.**

```bash
./deployment/scripts/deploy.sh status
```

Shows the ArgoCD apps, pods, secret sync, and the load balancer address. The
load balancer takes 3–5 minutes to appear. Open `http://<address>`: plain
HTTP until you add a certificate.

**Load balancer and Ingress.** Yes, both are part of this deployment.
`deployment/k8s/base/ingress.yaml` is a Kubernetes Ingress (`ingressClassName:
alb`, internet-facing, `target-type: ip`, HTTP port 80) that sends `/` to the
`frontend` Service on port 8080. The AWS Load Balancer Controller installed by
`addons` sees it and creates the Application Load Balancer; nginx in the
frontend pods then forwards `/api/` and `/ads-media/` to the backend.
Terraform does not create this ALB, which is why `destroy` removes it first.

> `deploy.sh all` runs apply → addons → secrets → configure → build → push →
> argocd in one go, then tells you to commit. Doing the steps one at a time is
> easier to debug on a first bring-up.

### Deploying changes

With [GitHub Actions](#4-one-click-deploy-and-cicd-github-actions) set up, pushing to `devops` does this for you. By hand:

```bash
git add -A && git commit -m "Your change"
./deployment/scripts/deploy.sh build
./deployment/scripts/deploy.sh push
git add deployment/k8s/base && git commit -m "Deploy new image" && git push origin devops
```

ArgoCD sees the new tag and does a rolling update. To roll back, `git revert`
the commit that changed the tag in `kustomization.yaml`. ECR keeps the last 10
images of each repository.

---

## 4. One-click deploy and CI/CD (GitHub Actions)

Three workflows in `.github/workflows/` drive the same `deploy.sh` commands from GitHub. They sign in to AWS with OIDC, so **no AWS keys are stored anywhere**.

| Workflow | Starts when | What it does |
|---|---|---|
| **Deploy infrastructure** (`deploy.yml`) | You click *Run workflow* | Builds everything: VPC, EKS, RDS, add-ons, images, ArgoCD. About 30-40 minutes. Prints the site URL in the run summary. |
| **Release** (`release.yml`) | Push to `devops` that changes `backend/`, `frontend/` or `deployment/docker/` | Builds and pushes new images, commits the new tag, ArgoCD rolls it out. Does nothing if the cluster isn't deployed. |
| **Destroy infrastructure** (`destroy.yml`) | You click *Run workflow* and type `destroy` | Removes the load balancer, empties ECR, destroys everything, and frees the secret names so you can redeploy at once. Tick the box to also delete the final DB snapshot. |

### One-time setup (about 10 minutes)

**0. Prepare the repository.** Do this once, before the first push:

```bash
git checkout devops                     # the deployable, default branch

# Remove files from older layouts if they exist
git rm -f --ignore-unmatch .github/workflows/deploy.yaml argocd/application.yaml

# Never commit Terraform state: it contains the database password
printf '%s\n' '*.tfstate' '*.tfstate.*' '.terraform/' '.env' 'node_modules/' >> .gitignore
git ls-files | grep -E 'tfstate|\.env$' && echo "REMOVE THESE: git rm --cached <file>"

# Scripts must start with a shebang, be executable, and use Unix line endings
head -1 deployment/scripts/*.sh                        # each must print #!/usr/bin/env bash
sed -i 's/\r$//' deployment/scripts/*.sh .github/workflows/*.yml
chmod +x deployment/scripts/*.sh
git add -A
git update-index --chmod=+x deployment/scripts/deploy.sh deployment/scripts/bootstrap.sh
git ls-files -s deployment/scripts/                    # both must show mode 100755

git commit -m "Add GitHub Actions CI/CD" && git push origin devops
```

Both `argocd/root-app.yaml` and `argocd/apps/yt-viewer-tracker.yaml` must say `targetRevision: devops`. The *Run workflow* button only appears for workflows that are on the repository's default branch.

**1. Run the bootstrap script** with your own admin login, in a terminal or AWS CloudShell:

```bash
bash deployment/scripts/bootstrap.sh
```

It creates the Terraform state bucket and lock table, the GitHub OIDC provider, and the IAM role `yt-viewer-tracker-gha-deployer`, which only this repo's `production` environment can use. These live **outside** the main Terraform on purpose: a destroy must not delete its own state or the role it is running as. At the end it prints the values for step 2.

**2. In GitHub** (repo, then Settings):

| Where | What |
|---|---|
| Environments, new environment | Name it `production`. Optional: add *Required reviewers* for an approval before every run, and restrict *Deployment branches* to `devops`. |
| Secrets and variables, Actions, **Variables** | `AWS_ROLE_ARN` = the role ARN the script printed |
| Environment `production`, **Secrets** | `YOUTUBE_API_KEY` = your key. Optional: `DB_PASSWORD` = your own RDS password (generated if unset). |
| Actions, General, Workflow permissions | *Read and write permissions* (workflows commit the image tag) |

**3. Open Actions, Deploy infrastructure, Run workflow** (branch `devops`). The first run takes about 30-40 minutes. When it finishes, the run summary shows the site URL; the load balancer can need another 3-5 minutes before it answers.

**4. Check the Release workflow:** change a line in `frontend/` or `backend/`, push to `devops`, and watch Actions build the image, commit the new tag, and ArgoCD roll it out.

**Your own `kubectl` access.** The cluster is created by the GitHub role, so your own IAM user is not automatically an admin of it. To run `kubectl` yourself, add an access entry for your user:

```bash
aws eks create-access-entry --cluster-name yt-viewer-tracker --principal-arn <your-iam-user-or-role-arn>
aws eks associate-access-policy --cluster-name yt-viewer-tracker --principal-arn <your-iam-user-or-role-arn> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
aws eks update-kubeconfig --name yt-viewer-tracker --region ap-south-1
```

### Day to day

- **Ship a change:** push to `devops`. The Release workflow builds, tags with the commit ID, commits the tag, and ArgoCD deploys it. Roll back by reverting the tag commit.
- **Stop paying:** run **Destroy infrastructure**. Run **Deploy infrastructure** again whenever you want it back.
- A cold deploy can occasionally time out while Fargate pods start; re-running the workflow continues from where it stopped (Terraform and the add-on installs are safe to repeat).

**Security note:** the deployer role has `AdministratorAccess`, because Terraform creates IAM roles, EKS and RDS. Anyone who can push to `devops` or run a workflow in the `production` environment can use it. Protect `devops` with branch protection, and add required reviewers to the environment if more than one person has write access.

**Cost note:** the state bucket and lock table cost cents per month and stay after a destroy. The environment itself costs about $320-370 a month while it exists (see [Cost estimate](#cost-estimate)).

---

## Secrets

Nothing sensitive is stored in this repository.

| Value | Where it lives | Set by |
|---|---|---|
| RDS master password | Terraform state (generated, or `TF_VAR_db_password`) | Terraform / you |
| `DATABASE_URL` | Secrets Manager `yt-viewer-tracker/database-url` | Terraform, automatically |
| `YOUTUBE_API_KEY` | Secrets Manager `yt-viewer-tracker/api-keys` | You (`deploy.sh secrets`) |
| `ADS_API_KEY` | Same secret | Placeholder; only used if you set `ADS_API_URL` |
| AWS access for pods | IRSA: one IAM role per service account | n/a |

External Secrets Operator copies both secrets into one Kubernetes Secret
(`backend-secrets`) and refreshes it every hour.

**Change the YouTube key later:**

```bash
aws secretsmanager put-secret-value --secret-id yt-viewer-tracker/api-keys \
  --secret-string '{"YOUTUBE_API_KEY":"new-key","ADS_API_KEY":"REPLACE_ME_VIA_AWS_CLI_NOT_TERRAFORM"}'
kubectl annotate externalsecret backend-secrets -n yt-viewer-tracker force-sync=$(date +%s) --overwrite
kubectl rollout restart deployment backend -n yt-viewer-tracker
```

The restart matters: the backend reads its settings once at startup, so it
keeps the old key until the pod restarts.

---

## Terraform reference

`deployment/terrafrom/main.tf` connects the modules; the modules contain no
app-specific values.

| Module | Creates |
|---|---|
| `vpc` | VPC, public and private subnets, NAT gateway, route tables, EKS subnet tags |
| `eks-fargate` | EKS cluster, Fargate profiles, pod execution role with ECR pull access |
| `rds-postgres` | Private encrypted PostgreSQL; your password or a generated one |
| `ecr` | One immutable, scanned repository per image, with cleanup |
| `app-secrets` | The two Secrets Manager secrets |
| `irsa-role` | An IAM role exactly one Kubernetes service account can assume |
| `github-oidc` | IAM roles GitHub Actions could use without stored AWS keys |
| `prometheus` | Amazon Managed Prometheus workspace |

Fargate profiles exist for `kube-system`, `external-secrets`, `argocd`,
`aws-observability`, and the app namespace. Add more with
`extra_fargate_namespaces`.

**Outputs** (`terraform output`, read by `deploy.sh`): `eks_cluster_name`,
`vpc_id`, `rds_endpoint`, `ecr_backend_repository_url`,
`ecr_frontend_repository_url`, `api_keys_secret_name`,
`database_url_secret_name`, `external_secrets_role_arn`,
`adot_collector_role_arn`, `lb_controller_role_arn`,
`github_actions_role_arn`, `amp_workspace_endpoint`, `tf_state_bucket`.

**Kubernetes version.** Set by `eks_cluster_version` in `deployment/terrafrom/variables.tf` (default `1.35`). EKS supports each version for about 14 months, then charges extra for extended support and eventually upgrades the cluster for you. Check the [EKS version calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) every few months. On a running cluster, upgrade one minor version at a time (change the variable, `deploy.sh apply`), then restart the Fargate pods so they pick up the new kubelet: `kubectl rollout restart deployment -n yt-viewer-tracker` (and the same for the other namespaces).

**Using the Terraform for another app:** copy `deployment/terrafrom`, change
`local.name` in `main.tf` and the values in `terraform.tfvars`, give the VPC a
different `cidr_block`, and set `create_github_oidc_provider = false` (an AWS
account can have only one GitHub OIDC provider).

---

## Configuration reference

Backend environment variables. In Kubernetes, the non-secret ones are in
`deployment/k8s/base/backend-configmap.yaml`.

| Variable | Default | Description |
|---|---|---|
| `YOUTUBE_API_KEY` | none | YouTube Data API v3 key (secret) |
| `DATABASE_URL` | none | PostgreSQL connection string (secret) |
| `PGSSL` | `false` locally, `true` in Compose and Kubernetes | Use SSL to connect (RDS expects it) |
| `PORT` | `4000` | Backend HTTP port |
| `POLL_INTERVAL_MS` | `180000` | How often viewer counts are read (3 min) |
| `LIVE_LOOKUP_REFRESH_MS` | `3600000` | Scheduled stream discovery (1 h) |
| `REACTIVE_REDISCOVER_COOLDOWN_MS` | `1800000` | Shortest gap between discoveries triggered by a stream ending |
| `ADS_API_URL`, `ADS_API_KEY` | empty | Optional external ad API; otherwise ads come from `backend/ads.json` |

**Quota math:** reading viewer counts costs 1 unit per call (up to 50 videos
per call); discovery costs 100 units per channel per run. With 2 channels, a
3-minute poll, and hourly discovery: about 480 + 4,800 = 5,280 of the 10,000
daily units.

---

## Monitoring

| What | Where |
|---|---|
| Container logs | CloudWatch Logs, group `/aws/eks/yt-viewer-tracker-production/fargate` |
| Metrics | Amazon Managed Prometheus; point Grafana at its query endpoint |
| Health | Frontend `/health`, backend `/healthz` |
| Raw metrics | Backend `/metrics` (Prometheus format) |

Fargate can't run DaemonSets or attach EBS volumes, so a self-hosted
Prometheus or a CloudWatch agent isn't an option. Logs go through Fargate's
built-in Fluent Bit; metrics go through an ADOT Collector Deployment.

---

## Limitations and next steps

- **Releases are automatic only on `devops`.** Pushes to other branches build nothing. For the manual route see *Deploying changes*.
- **Terraform state is in S3** (versioned, encrypted, locked with DynamoDB), created by `bootstrap.sh`. It contains your database password, so keep access to that bucket tight. Deleting the bucket or lock table by hand loses track of what Terraform built.
- **HTTP only.** For HTTPS, request an ACM certificate and enable the commented annotations in `deployment/k8s/base/ingress.yaml`.
- **Single-AZ database, no deletion protection.** Set `db_multi_az = true` for a standby; the final snapshot on destroy is the only safeguard against accidental deletion.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Pods `ImagePullBackOff` or `InvalidImageName` | `kustomization.yaml` in git still has `REPLACE_WITH_ECR_*` placeholders or an unpushed tag. Run `deploy.sh push`, commit the file, push to `devops`. |
| Backend `CreateContainerConfigError` | The `backend-secrets` Secret doesn't exist. Run `kubectl describe externalsecret backend-secrets -n yt-viewer-tracker`. Usually the role ARN in `external-secrets-sa.yaml` wasn't committed (re-run `deploy.sh configure`), or the API key was never set (`deploy.sh secrets`). |
| Ingress has no `ADDRESS` | Wait 3–5 minutes, then check `kubectl logs -n kube-system deploy/aws-load-balancer-controller`. Permission errors mean the controller is missing its IAM role: re-run `deploy.sh addons`. |
| Pods stuck `Pending` | No Fargate profile covers that namespace (see *Terraform reference*). |
| ArgoCD stays `OutOfSync` or can't find files | It reads the branch in `targetRevision`. Make sure that is `devops` in both Application files and that your commits are pushed to it. |
| `deploy.sh addons`: `coredns ... exceeded its progress deadline` | CoreDNS predates the Fargate profile. Current `deploy.sh` patches and restarts it automatically; with an older copy, run the commands in Step 6, then re-run `addons`. |
| `deploy.sh argocd`: `no matches for kind "Application"` | ArgoCD isn't installed yet. Run `deploy.sh addons` first and check `kubectl get crd \| grep argoproj`. |
| `kubectl apply` of ArgoCD: `metadata.annotations: Too long` | Use `kubectl apply --server-side` (`deploy.sh addons` already does). |
| ArgoCD sync error `failed calling webhook ... x509: certificate is valid for ip-...compute.internal` | The External Secrets webhook defaults to port 10250, which on Fargate is the kubelet's port. Install it with `--set webhook.port=9443` (set in the `deploy.sh` provided with this README; add it to the `helm upgrade --install external-secrets` line if yours lacks it), or fix a running cluster with `helm upgrade external-secrets external-secrets/external-secrets -n external-secrets --reuse-values --set webhook.port=9443`. |
| ExternalSecret `SecretSyncedError`: `unable to unmarshal secret ... invalid character 'p'` | `database-url` is a plain string, not JSON. In `external-secret.yaml`, read it under `spec.data` (`secretKey: DATABASE_URL`) and only `api-keys` under `spec.dataFrom`. Both lists sit directly under `spec`, not under `target`. |
| Backend pod `0/1 Running`, restarting; `/healthz` returns 404 | `backend/server.js` lacks the `/healthz` and `/metrics` routes the probes and ADOT collector use. Add them, rebuild (`deploy.sh build`, `push`), commit the new tag. |
| `destroy` fails: `DBSnapshotAlreadyExists` for `yt-viewer-tracker-db-final-snapshot` | A final snapshot from an earlier destroy still exists. `deploy.sh destroy` now replaces it automatically. By hand: `aws rds delete-db-snapshot --db-snapshot-identifier yt-viewer-tracker-db-final-snapshot`, then destroy again. |
| Destroy workflow: `the server has asked for the client to provide credentials` in the pre-destroy step | The cluster was created by someone else (for example your own IAM user), so the GitHub role has no Kubernetes access and can't remove the load balancer. Delete the ArgoCD apps and Ingress yourself, or add an access entry for `yt-viewer-tracker-gha-deployer` (`aws eks create-access-entry`, then `associate-access-policy` with `AmazonEKSClusterAdminPolicy`). Clusters built by the Deploy workflow don't have this problem. |
| `destroy` fails: `RepositoryNotEmptyException` on ECR | The repositories still hold images. Empty them (`aws ecr batch-delete-image` on each, or delete the images in the console) and run `deploy.sh destroy` again. |
| `State bucket '...' not found. Run bootstrap.sh once first` | The remote state hasn't been created in this AWS account. Run `./deployment/scripts/bootstrap.sh`. |
| Workflow: `Could not assume role with OIDC` / `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `AWS_ROLE_ARN` is wrong or missing, the job isn't in the `production` environment, or the repo name given to `bootstrap.sh` differs from your GitHub repo (re-run it with `GITHUB_REPO=owner/name`). |
| Workflow: `Not authorized to perform sts:AssumeRoleWithWebIdentity` even though the role ARN and trust policy look right | GitHub now puts numeric IDs in the token subject (`repo:owner@<id>/name@<id>:environment:production`). The trust policy must list that form. Re-run `bootstrap.sh` from this repo (it looks the IDs up and accepts both forms), or set `GITHUB_OWNER_ID` and `GITHUB_REPO_ID` yourself. To see what GitHub sends, print the OIDC token's `sub` in a temporary workflow step. |
| Workflow can't push the tag commit (`403` / `protected branch`) | Enable *Read and write permissions* under Settings, Actions, General. If `devops` is protected, allow the Actions bot to push, or use a PAT. |
| Workflow step fails with `Permission denied` or `bad interpreter` on a script | The script lost its executable bit, has no `#!/usr/bin/env bash` first line, or has Windows line endings. Run the commands in *One-time setup, step 0*, commit and push. |
| `Run workflow` button missing | The workflow file isn't on the default branch. Push it to `devops` and make sure `devops` is the default branch under Settings, Branches. |
| `terraform.tfstate` shows up in `git status` | Add `*.tfstate*` to `.gitignore`. If it was ever committed, run `git rm --cached` on it and treat the database password as exposed: set a new `DB_PASSWORD` secret before the next deploy. |
| `exec format error` in pod logs | Images were built on an ARM machine. EKS Fargate runs x86: build on an Intel/AMD machine. |
| `403 quotaExceeded` in backend logs | The daily YouTube quota is used up. Pin more `videoIds`, or raise `LIVE_LOOKUP_REFRESH_MS`. |
| Compose: backend can't connect to the database | A timeout means the network path is blocked (RDS security group, VPC). An authentication error usually means an un-encoded special character in the password. `database "..." does not exist` means the name at the end of the URL isn't on that server. |
| `deploy.sh: $'\r': command not found` | The script has Windows line endings. Run `sed -i 's/\r$//' deployment/scripts/deploy.sh`, and run `git config core.autocrlf input` on the Windows machine. |
| After `destroy`: "secret ... already scheduled for deletion" | Secrets Manager keeps deleted secrets for 7 days. Wait, or for each of `yt-viewer-tracker/api-keys` and `yt-viewer-tracker/database-url` run `aws secretsmanager restore-secret --secret-id <name>` and then `aws secretsmanager delete-secret --secret-id <name> --force-delete-without-recovery`. |

---

## Architecture decisions

- **Secrets come from Secrets Manager through External Secrets Operator, never from git.** A Secret manifest in a GitOps repo has to hold real values, and hand-made Secrets must be redone for every new cluster. Here, Terraform writes `DATABASE_URL`, you write the API key once, and the cluster keeps itself in sync.
- **Two secrets, not one.** `database-url` is owned by Terraform and updates when the password changes. `api-keys` is yours, and Terraform never touches it after creation (`ignore_changes`).
- **The backend runs exactly 1 replica, on purpose.** The poller's discovery cache lives in process memory. A second replica would poll YouTube independently, doubling quota use and writing duplicate readings. Scaling the API separately needs the poller split into its own process.
- **Images are tagged with the commit ID, and ECR tags are immutable.** A tag always means one exact build, and rollback is a `git revert`. There is no `:latest`.
- **`/healthz` doesn't check the database.** A brief database problem shouldn't make Kubernetes kill a healthy process.
- **Fargate instead of EC2 nodes:** nothing to patch or scale. The cost: every pod is billed on its own, including the system pods.
- **One NAT gateway, not one per AZ.** It saves about $35 a month; if its AZ goes down, the others lose outbound internet until it recovers.
- **App of apps.** `root-app.yaml` is the only Application applied by hand. A new service is a file in `argocd/apps/`.

---

## Cost estimate

Approximate monthly cost in `ap-south-1`, before tax, light traffic. Check the
[AWS Pricing Calculator](https://calculator.aws/) for current prices.

**EKS deployment**

| Resource | Spec | USD / month |
|---|---|---|
| EKS control plane | 1 cluster | ~$73 |
| Fargate pods | app + system pods | ~$160–180 |
| RDS PostgreSQL | db.t4g.micro, 20 GB, single-AZ | ~$15–20 |
| NAT gateway | 1, plus data | ~$35–45 |
| Application Load Balancer | 1 | ~$20–25 |
| Public IPv4 addresses, Secrets Manager, ECR, Prometheus, logs | | ~$15–25 |
| **Total** | | **~$320–370** |

**One EC2 instance with Docker Compose and an existing RDS**

| Resource | Spec | USD / month |
|---|---|---|
| EC2 | t3.small / t3.medium | ~$15–17 / ~$30–35 |
| EBS | 30 GB gp3 | ~$3 |
| Public IPv4 address | 1 | ~$4 |
| RDS PostgreSQL | db.t4g.micro | ~$15–20 |
| **Total** | | **~$40–65** |

---

## Teardown

With GitHub Actions: **Actions, Destroy infrastructure, Run workflow**, type `destroy`. By hand:

```bash
./deployment/scripts/deploy.sh destroy
```

**Use this, not a plain `terraform destroy`.** The load balancer is created by
the Load Balancer Controller, outside Terraform, and while it exists the VPC
can't be deleted: a plain destroy hangs and then fails. `destroy` deletes the
ArgoCD apps and the Ingress first, waits until the load balancer is really
gone, empties the ECR repositories, and only then runs Terraform. State is in S3, so you can run it from any machine with admin access.

RDS keeps a final snapshot, `yt-viewer-tracker-db-final-snapshot`. Delete it by
hand if you don't need it, since it keeps costing storage. A second `destroy`
fails while that snapshot name exists.

---

## Contributing

1. Create a branch: `git checkout -b feature/my-change`
2. Run it locally and check your change
3. Open a pull request against `devops`

## License

Add a `LICENSE` file to say how others may use this code. Until then, the
default is "all rights reserved".

## Author

**Md Wasim Akram** · [@wasim0028](https://github.com/wasim0028)
