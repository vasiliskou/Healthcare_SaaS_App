#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Config (with sane defaults)
# -----------------------------
ENVIRONMENT="${ENVIRONMENT:-dev}"            # dev | staging | prod
PROJECT_NAME="${PROJECT_NAME:-consultation-app}"
AWS_REGION="${AWS_REGION:-eu-west-3}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Terraform vars via environment (picked up automatically as TF_VAR_*)
export TF_VAR_openai_api_key="${OPENAI_API_KEY:-}"
export TF_VAR_clerk_secret_key="${CLERK_SECRET_KEY:-}"
export TF_VAR_clerk_jwks_url="${CLERK_JWKS_URL:-}"
export TF_VAR_clerk_issuer="${TF_VAR_clerk_issuer:-https://your-clerk-subdomain.clerk.accounts.dev}"
export TF_VAR_clerk_jwt_audience="${TF_VAR_clerk_jwt_audience:-fastapi}"

echo
echo "Deploying ${PROJECT_NAME} (${ENVIRONMENT} environment)..."

# -----------------------------
# Paths (repo root = parent of this script dir)
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

BACKEND_DIR="${REPO_ROOT}/backend"
FRONTEND_DIR="${REPO_ROOT}/frontend"
INFRA_DIR="${REPO_ROOT}/infra"
INFRA_ECR="${INFRA_DIR}/ecr"
INFRA_AR="${INFRA_DIR}/apprunner"
INFRA_FE="${INFRA_DIR}/frontend"

for p in "${INFRA_ECR}" "${INFRA_AR}" "${INFRA_FE}"; do
  [[ -d "$p" ]] || { echo "Folder not found: $p" >&2; exit 1; }
done

# -----------------------------
# Tool checks
# -----------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 1; }; }
for cmd in aws docker terraform node npm; do need "$cmd"; done

# -----------------------------
# AWS identity / ECR info
# -----------------------------
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ -n "${AWS_ACCOUNT_ID}" ]] || { echo "Could not determine AWS Account ID." >&2; exit 1; }

ECR_HOST="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPO="${PROJECT_NAME}"
ECR_URL="${ECR_HOST}/${ECR_REPO}"

echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR URL:     ${ECR_URL}"

# -----------------------------
# [1] Terraform: ECR
# -----------------------------
echo
echo "=== [ECR] terraform init/apply ==="
terraform -chdir="${INFRA_ECR}" init -upgrade
terraform -chdir="${INFRA_ECR}" apply -auto-approve \
  -var="project_name=${PROJECT_NAME}" \
  -var="aws_region=${AWS_REGION}" \
  -var="ecr_repo_name=${ECR_REPO}" \
  -var="image_tag=${IMAGE_TAG}"

# -----------------------------
# [2] Docker build & push
# -----------------------------
echo
echo "=== [Docker] Login, build, tag, push ==="
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_HOST}"

# Build for linux/amd64 so App Runner can run it
docker build \
  --platform linux/amd64 \
  -t "${PROJECT_NAME}:${IMAGE_TAG}" \
  -f "${BACKEND_DIR}/Dockerfile" \
  "${BACKEND_DIR}"

docker tag "${PROJECT_NAME}:${IMAGE_TAG}" "${ECR_URL}:${IMAGE_TAG}"
docker push "${ECR_URL}:${IMAGE_TAG}"

# -----------------------------
# [3] Terraform: App Runner
# -----------------------------
echo
echo "=== [App Runner] terraform init/apply ==="
terraform -chdir="${INFRA_AR}" init -upgrade
terraform -chdir="${INFRA_AR}" apply -auto-approve \
  -var="project_name=${PROJECT_NAME}" \
  -var="aws_region=${AWS_REGION}" \
  -var="ecr_repo_name=${ECR_REPO}" \
  -var="image_tag=${IMAGE_TAG}" \
  -var="container_port=8000" \
  -var="health_check_path=/health" \
  -var="apprunner_cpu=256" \
  -var="apprunner_memory=512" \
  -var="apprunner_min_size=1" \
  -var="apprunner_max_size=1" \
  -var="apprunner_max_concurrency=10"

# Read App Runner outputs (no jq required)
echo
echo "=== [App Runner] outputs ==="
set +e
SERVICE_URL="$(terraform -chdir="${INFRA_AR}" output -raw apprunner_service_url 2>/dev/null)"
SERVICE_STATUS="$(terraform -chdir="${INFRA_AR}" output -raw service_status 2>/dev/null)"
set -e
if [[ -n "${SERVICE_URL:-}" ]]; then
  echo "Backend URL: ${SERVICE_URL}"
else
  echo "Backend URL not found in outputs (apprunner_service_url)."
fi
if [[ -n "${SERVICE_STATUS:-}" ]]; then
  echo "Service status: ${SERVICE_STATUS}"
fi

# Export for frontend build
export NEXT_PUBLIC_API_URL="${SERVICE_URL:-}"

# -----------------------------
# [4] Terraform: Frontend infra (S3 + CloudFront)
# -----------------------------
echo
echo "=== [Frontend] terraform init/apply (S3 + CloudFront) ==="
terraform -chdir="${INFRA_FE}" init -upgrade

# Leave custom domain fields empty to use *.cloudfront.net
FRONTEND_DOMAIN_NAME="${FRONTEND_DOMAIN_NAME:-}"
FRONTEND_ACM_ARN="${FRONTEND_ACM_ARN:-}"

terraform -chdir="${INFRA_FE}" apply -auto-approve \
  -var="project_name=${PROJECT_NAME}" \
  -var="aws_region=${AWS_REGION}" \
  -var="frontend_domain_name=${FRONTEND_DOMAIN_NAME}" \
  -var="frontend_acm_certificate_arn=${FRONTEND_ACM_ARN}"

# Read frontend outputs
echo
echo "=== [Frontend] outputs ==="
S3_BUCKET_NAME="$(terraform -chdir="${INFRA_FE}" output -raw s3_bucket_name)"
CF_DIST_ID="$(terraform -chdir="${INFRA_FE}" output -raw cloudfront_distribution_id)"
CF_URL="$(terraform -chdir="${INFRA_FE}" output -raw cloudfront_distribution_url || true)"

echo "S3 bucket: ${S3_BUCKET_NAME}"
echo "CloudFront distribution: ${CF_DIST_ID}"
if [[ -n "${CF_URL:-}" ]]; then
  echo "CloudFront URL: ${CF_URL}"
fi

# -----------------------------
# [5] Frontend build, upload, invalidate
# -----------------------------
echo
echo "=== [Frontend] build and upload ==="
[[ -d "${FRONTEND_DIR}" ]] || { echo "Frontend directory not found: ${FRONTEND_DIR}" >&2; exit 1; }

pushd "${FRONTEND_DIR}" >/dev/null

npm ci
echo "Building frontend with NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}"
npm run build

# Detect Next.js; run static export if needed
if [[ -f "package.json" ]] && grep -q '"next"' package.json; then
  if [[ ! -d "out" ]]; then
    echo "Detected Next.js; running 'npx next export' to generate static 'out/'."
    npx next export
  fi
fi

# Resolve build output dir
resolve_dist() {
  for d in "out" "dist" "build"; do
    [[ -d "$d" ]] && { echo "$d"; return; }
  done
  # Fallback: any dir (depth 2) containing index.html
  # shellcheck disable=SC2044
  for d in $(find . -maxdepth 2 -type d); do
    [[ -f "${d}/index.html" ]] && { echo "${d#./}"; return; }
  done
  return 1
}

DIST_DIR="$(resolve_dist || true)"
if [[ -z "${DIST_DIR:-}" ]]; then
  echo "Could not locate build output directory. Looked for 'out', 'dist', 'build', or any folder containing index.html." >&2
  popd >/dev/null
  exit 1
fi

echo "Using build output: ${DIST_DIR}"

echo
echo "=== [Frontend] sync to S3 ==="
# 1) Sync everything except index.html with long cache (immutable)
aws s3 sync "${DIST_DIR}" "s3://${S3_BUCKET_NAME}" \
  --delete \
  --cache-control "public,max-age=31536000,immutable" \
  --exclude "index.html"

# 2) Upload index.html with no-cache (ensures SPA updates immediately)
if [[ -f "${DIST_DIR}/index.html" ]]; then
  aws s3 cp "${DIST_DIR}/index.html" "s3://${S3_BUCKET_NAME}/index.html" \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "text/html"
else
  echo "[Info] index.html not found in ${DIST_DIR} - skipping no-cache override."
fi

echo
echo "=== [Frontend] CloudFront invalidation ==="
# Invalidate everything (simple); for cheaper/faster, invalidate only HTML/manifest
aws cloudfront create-invalidation --distribution-id "${CF_DIST_ID}" --paths "/*" >/dev/null || \
  echo "[Warn] Invalidation failed; distribution might still be deploying."

popd >/dev/null

echo
echo "===================="
echo "Deployment complete."
if [[ -n "${SERVICE_URL:-}" ]]; then
  echo "API:        ${SERVICE_URL}"
fi
if [[ -n "${CF_URL:-}" ]]; then
  echo "Frontend:   ${CF_URL}"
fi
