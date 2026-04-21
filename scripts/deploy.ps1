param(
  [string]$Environment = "dev",   # dev | staging | prod
  [string]$ProjectName = "consultation-app",
  [string]$AwsRegion   = "eu-west-3",
  [string]$ImageTag    = "latest"
)

# # --- Export secrets to Terraform (TF_VAR_...) ---
$env:TF_VAR_openai_api_key     = $env:OPENAI_API_KEY
$env:TF_VAR_clerk_secret_key   = $env:CLERK_SECRET_KEY
$env:TF_VAR_clerk_jwks_url     = $env:CLERK_JWKS_URL
$env:TF_VAR_clerk_issuer       = "https://your-clerk-subdomain.clerk.accounts.dev"
$env:TF_VAR_clerk_jwt_audience = "fastapi"

# Stop immediately if any error occurs
$ErrorActionPreference = "Stop"

Write-Host "`n Deploying $ProjectName ($Environment environment) ..." -ForegroundColor Green

# --- Paths ---
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$BackendDir = Join-Path $RepoRoot "backend"
$FrontendDir = Join-Path $RepoRoot "frontend"
$InfraDir   = Join-Path $RepoRoot "infra"
$InfraDirECR = Join-Path $InfraDir "ecr"
$InfraDirAR  = Join-Path $InfraDir "apprunner"


# --- Sanity checks ---
foreach ($cmd in @("aws","docker","terraform","node","npm")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw " Required command not found: $cmd"
  }
}

# --- AWS & ECR setup ---
$AwsAccountId = (aws sts get-caller-identity --query "Account" --output text)
if (-not $AwsAccountId) { throw " Could not determine AWS Account ID (check AWS CLI credentials/profile)." }

$EcrHost = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
$EcrRepo = $ProjectName
$EcrUrl  = "$EcrHost/$EcrRepo"

Write-Host "InfraDirECR = $InfraDirECR"
if (-not (Test-Path $InfraDirECR)) {
  throw " Folder not found: $InfraDirECR"
}

terraform -chdir="$InfraDirECR" init
$ecrApplyArgs = @(
  "apply",
  "-auto-approve",
  "-var=project_name=$ProjectName",
  "-var=aws_region=$AwsRegion",
  "-var=ecr_repo_name=$EcrRepo",
  "-var=image_tag=$ImageTag"
)
terraform -chdir="$InfraDirECR" @ecrApplyArgs

# --- Docker build & push ---
Set-Location $RepoRoot
Write-Host "`n Logging into Amazon ECR..." -ForegroundColor Yellow
Write-Host "EcrHost=$EcrHost  AwsRegion=$AwsRegion  Account=$AwsAccountId"
aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $EcrHost

Write-Host "`n Building Docker image..." -ForegroundColor Yellow
docker build `
  --platform linux/amd64 `
  -t "$($ProjectName):$ImageTag" `
  -f (Join-Path $BackendDir "Dockerfile") `
  $BackendDir

# Make sure the image you built is tagged to the full ECR URL before pushing
docker tag "$($ProjectName):$ImageTag" "$($EcrUrl):$ImageTag"

Write-Host "`n Pushing Docker image to ECR ..." -ForegroundColor Yellow
docker push "$($EcrUrl):$ImageTag"

# --- App Runner infrastructure ---
Write-Host "`n=== [App Runner] Creating/Updating infrastructure ===" -ForegroundColor Yellow

if (-not (Test-Path $InfraDirAR)) {
  throw " Folder not found: $InfraDirAR"
}

terraform -chdir="$InfraDirAR" init

# Match your apprunner module's variable names
# (Using the autoscaling = 1 instance config you asked for)
$arApplyArgs = @(
  "apply",
  "-auto-approve",
  "-var=project_name=$ProjectName",
  "-var=aws_region=$AwsRegion",
  "-var=ecr_repo_name=$EcrRepo",
  "-var=image_tag=$ImageTag",
  "-var=container_port=8000",
  "-var=health_check_path=/health",
  "-var=apprunner_cpu=256",
  "-var=apprunner_memory=512",
  "-var=apprunner_min_size=1",
  "-var=apprunner_max_size=1",
  "-var=apprunner_max_concurrency=10"
)

terraform -chdir="$InfraDirAR" @arApplyArgs

# Read and print outputs (URL, status)
try {
  $arJson = terraform -chdir="$InfraDirAR" output -json
  $arOut  = $arJson | ConvertFrom-Json

  $ServiceUrl    = $arOut.apprunner_service_url.value
  $ServiceStatus = $arOut.service_status.value

  if ($ServiceUrl)    { Write-Host "`n App Runner URL: $ServiceUrl" -ForegroundColor Green }
  if ($ServiceStatus) { Write-Host "Status: $ServiceStatus" -ForegroundColor Cyan }
} catch {
  Write-Host "Could not read App Runner outputs (yet)." -ForegroundColor DarkYellow
}

# =========================
# === Frontend deploy ===
# =========================
Write-Host "`n=== [Frontend] Creating/Updating infrastructure ===" -ForegroundColor Yellow

$InfraDirFE = Join-Path $InfraDir "frontend"
if (-not (Test-Path $InfraDirFE)) {
  throw "Frontend Terraform folder not found: $InfraDirFE"
}

terraform -chdir="$InfraDirFE" init -upgrade

# If you don't use a custom domain, keep these empty:
$FrontendDomainName = ""
$FrontendAcmArn     = ""

$feApplyArgs = @(
  "apply",
  "-auto-approve",
  "-var=project_name=$ProjectName",
  "-var=aws_region=$AwsRegion",
  "-var=frontend_domain_name=$FrontendDomainName",
  "-var=frontend_acm_certificate_arn=$FrontendAcmArn"
)
terraform -chdir="$InfraDirFE" @feApplyArgs

# --- Read frontend outputs ---
try {
  $feJson = terraform -chdir="$InfraDirFE" output -json
  $feOut  = $feJson | ConvertFrom-Json

  $FrontendBucket = $feOut.s3_bucket_name.value
  $CfDistId       = $feOut.cloudfront_distribution_id.value
  $CfUrl          = $feOut.cloudfront_distribution_url.value

  if (-not $FrontendBucket) { throw "Could not read s3_bucket_name from outputs." }
  if (-not $CfDistId)       { throw "Could not read cloudfront_distribution_id from outputs." }

  Write-Host "S3 bucket: $FrontendBucket" -ForegroundColor Green
  Write-Host "CloudFront distribution: $CfDistId" -ForegroundColor Green
}
catch {
  throw "Failed to read frontend Terraform outputs. $_"
}

# --- Build frontend (npm) ---
Write-Host "`n=== [Frontend] Building app ===" -ForegroundColor Yellow
if (-not (Test-Path $FrontendDir)) {
  throw "Frontend directory not found: $FrontendDir"
}

function Resolve-FrontendDist {
  param([string]$root)
  # Priority order
  $candidates = @(
    (Join-Path $root "out"),
    (Join-Path $root "dist"),
    (Join-Path $root "build")
  )
  foreach ($p in $candidates) {
    if (Test-Path $p) { return $p }
  }

  # Fallback: find a directory (depth 2) that contains index.html (helps Angular, etc.)
  $hit = Get-ChildItem -Path $root -Directory -Recurse -Depth 2 `
    | Where-Object { Test-Path (Join-Path $_.FullName "index.html") } `
    | Select-Object -First 1
  if ($hit) { return $hit.FullName }

  return $null
}

Push-Location $FrontendDir
try {
  # Install deps
  npm ci

  Write-Host "Building frontend with NEXT_PUBLIC_API_URL=$env:NEXT_PUBLIC_API_URL" -ForegroundColor Cyan
  $env:NEXT_PUBLIC_API_URL = $ServiceUrl

  # Basic build (whatever your package.json defines)
  npm run build

  # If it's a Next.js project, ensure a static export exists
  $pkg = $null
  $pkgPath = Join-Path $FrontendDir "package.json"
  if (Test-Path $pkgPath) {
    try { $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json } catch {}
  }
  $hasNext = $false
  if ($pkg) {
    $deps = @()
    if ($pkg.dependencies)     { $deps += $pkg.dependencies.PSObject.Properties.Name }
    if ($pkg.devDependencies)  { $deps += $pkg.devDependencies.PSObject.Properties.Name }
    $hasNext = $deps -contains "next"
  }

  if ($hasNext -and -not (Test-Path (Join-Path $FrontendDir "out"))) {
    Write-Host "Detected Next.js. Running 'npx next export' to generate static 'out/'..." -ForegroundColor Cyan
    npx next export
  }

  # Resolve dist folder
  $DistDir = Resolve-FrontendDist -root $FrontendDir
  if (-not $DistDir) {
    throw "Could not locate build output directory. Looked for 'out', 'dist', 'build', and any folder (depth 2) containing index.html."
  }

  Write-Host "Using build output: $DistDir" -ForegroundColor Green

  Write-Host "`n=== [Frontend] Uploading to S3 ===" -ForegroundColor Yellow

  # 1) Sync everything except index.html with long cache (immutable)
  aws s3 sync "$DistDir" "s3://$FrontendBucket" `
    --delete `
    --cache-control "public,max-age=31536000,immutable" `
    --exclude "index.html"

  # 2) Upload index.html with no-cache (ensures SPA updates instantly)
  $IndexFile = Join-Path $DistDir "index.html"
  if (Test-Path $IndexFile) {
    aws s3 cp "$IndexFile" "s3://$FrontendBucket/index.html" `
      --cache-control "no-cache, no-store, must-revalidate" `
      --content-type "text/html"
  } else {
    Write-Host "[Info] index.html not found in $DistDir - skipping no-cache override." -ForegroundColor DarkYellow
  }

  Write-Host "`n=== [Frontend] Creating CloudFront invalidation ===" -ForegroundColor Yellow
  try {
    # For cheaper/faster deploys, you could just invalidate HTML/manifest: "/index.html" "/app/*.html"
    aws cloudfront create-invalidation --distribution-id $CfDistId --paths "/*" | Out-Null
  }
  catch {
    Write-Host "[Warn] Invalidation failed; the distribution may still be deploying. Try again shortly." -ForegroundColor DarkYellow
  }

  if ($CfUrl) {
    Write-Host "`nFrontend available at: $CfUrl" -ForegroundColor Green
  } else {
    Write-Host "`nFrontend deployed. CloudFront URL output missing; check Terraform outputs." -ForegroundColor Green
  }
}
finally {
  Pop-Location
}
