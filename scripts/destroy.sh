#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Inputs (env vars with defaults)
# -----------------------------
ENVIRONMENT="${ENVIRONMENT:-dev}"              # dev | staging | prod
PROJECT_NAME="${PROJECT_NAME:-consultation-app}"
AWS_REGION="${AWS_REGION:-eu-west-3}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"          # "true" to skip confirmation
FORCE_DELETE_IMAGES="${FORCE_DELETE_IMAGES:-false}"  # "true" to empty ECR repo first

# Terraform vars (pulled from your CI secrets)
export TF_VAR_openai_api_key="${OPENAI_API_KEY:-}"
export TF_VAR_clerk_secret_key="${CLERK_SECRET_KEY:-}"
export TF_VAR_clerk_jwks_url="${CLERK_JWKS_URL:-}"
export TF_VAR_clerk_issuer="${TF_VAR_clerk_issuer:-https://your-clerk-subdomain.clerk.accounts.dev}"
export TF_VAR_clerk_jwt_audience="${TF_VAR_clerk_jwt_audience:-fastapi}"

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

for p in "${INFRA_FE}" "${INFRA_AR}" "${INFRA_ECR}"; do
  [[ -d "$p" ]] || { echo "Folder not found: $p" >&2; exit 1; }
done

# -----------------------------
# Tool checks
# -----------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 1; }; }
for cmd in aws terraform; do need "$cmd"; done

echo
echo "Destroying ${PROJECT_NAME} (${ENVIRONMENT} environment)..."

# -----------------------------
# AWS info
# -----------------------------
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ -n "${AWS_ACCOUNT_ID}" ]] || { echo "Could not determine AWS Account ID." >&2; exit 1; }

ECR_HOST="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPO="${PROJECT_NAME}"
ECR_URL="${ECR_HOST}/${ECR_REPO}"

# -----------------------------
# Confirm (unless AUTO_APPROVE=true)
# -----------------------------
if [[ "${AUTO_APPROVE}" != "true" ]] && [[ -t 0 ]]; then
  read -r -p "This will destroy Frontend (S3+CloudFront), App Runner, and ECR for '${PROJECT_NAME}' in ${AWS_REGION}. Proceed? (y/N) " ans
  if [[ ! "${ans}" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# -----------------------------
# Helpers
# -----------------------------
tf_destroy () {
  local dir="$1"; shift
  echo
  echo "=== Terraform destroy: ${dir} ==="
  terraform -chdir="${dir}" init -upgrade >/dev/null
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    terraform -chdir="${dir}" destroy -auto-approve "$@"
  else
    terraform -chdir="${dir}" destroy "$@"
  fi
}

common_vars=(
  "-var=project_name=${PROJECT_NAME}"
  "-var=aws_region=${AWS_REGION}"
)

# -----------------------------
# 1) Frontend (CloudFront + OAC + S3)
# -----------------------------
fe_vars=("${common_vars[@]}" "-var=frontend_domain_name=" "-var=frontend_acm_certificate_arn=")
tf_destroy "${INFRA_FE}" "${fe_vars[@]}"

# -----------------------------
# 2) App Runner (service + IAM role)
# -----------------------------
ar_vars=("${common_vars[@]}" "-var=ecr_repo_name=${ECR_REPO}" "-var=image_tag=${IMAGE_TAG}")
tf_destroy "${INFRA_AR}" "${ar_vars[@]}"

# -----------------------------
# 3) ECR images (optional), then ECR repo
# -----------------------------
if [[ "${FORCE_DELETE_IMAGES}" == "true" ]]; then
  echo
  echo "=== ECR: deleting images in ${ECR_REPO} (optional) ==="
  # list images (tagged/untagged); if any, batch delete
  if image_json="$(aws ecr list-images --region "${AWS_REGION}" --repository-name "${ECR_REPO}" --query 'imageIds' --output json)"; then
    count="$(echo "${image_json}" | jq 'length' 2>/dev/null || echo 0)"
    if [[ "${count}" -gt 0 ]]; then
      tmp="$(mktemp)"
      echo "${image_json}" > "${tmp}"
      aws ecr batch-delete-image --region "${AWS_REGION}" --repository-name "${ECR_REPO}" --image-ids "file://${tmp}" >/dev/null || true
      rm -f "${tmp}"
      echo "Deleted ${count} image(s) from ${ECR_REPO}"
    else
      echo "No images found in ${ECR_REPO}"
    fi
  else
    echo "Failed to list images for ${ECR_REPO}" >&2
  fi
else
  echo
  echo "Skipping ECR image deletion. If destroy fails due to non-empty repo, re-run with FORCE_DELETE_IMAGES=true."
fi

ecr_vars=("${common_vars[@]}" "-var=ecr_repo_name=${ECR_REPO}" "-var=image_tag=${IMAGE_TAG}")
tf_destroy "${INFRA_ECR}" "${ecr_vars[@]}"

echo
echo "All resources destroyed for ${PROJECT_NAME} (${ENVIRONMENT})."
