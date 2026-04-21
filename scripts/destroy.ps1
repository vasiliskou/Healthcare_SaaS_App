param(
  [string]$Environment = "dev",   # dev | staging | prod
  [string]$ProjectName = "consultation-app",
  [string]$AwsRegion   = "eu-west-3",
  [string]$ImageTag    = "latest",
  [switch]$AutoApprove,
  [switch]$ForceDeleteImages  # empties ECR repo before destroying it
)

# --- Export TF_VAR_* (harmless during destroy; keeps parity with deploy.ps1) ---
$env:TF_VAR_openai_api_key     = $env:OPENAI_API_KEY
$env:TF_VAR_clerk_secret_key   = $env:CLERK_SECRET_KEY
$env:TF_VAR_clerk_jwks_url     = $env:CLERK_JWKS_URL
$env:TF_VAR_clerk_issuer       = "https://your-clerk-subdomain.clerk.accounts.dev"
$env:TF_VAR_clerk_jwt_audience = "fastapi"

$ErrorActionPreference = "Stop"

function Require-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $name"
  }
}
foreach ($cmd in @("aws","terraform")) { Require-Command $cmd }

Write-Host "`nDestroying $ProjectName ($Environment environment) ..." -ForegroundColor Yellow

# --- Paths (same layout as your deploy.ps1) ---
$RepoRoot    = Split-Path -Parent $PSScriptRoot
$BackendDir  = Join-Path $RepoRoot "backend"
$FrontendDir = Join-Path $RepoRoot "frontend"
$InfraDir    = Join-Path $RepoRoot "infra"
$InfraDirECR = Join-Path $InfraDir "ecr"
$InfraDirAR  = Join-Path $InfraDir "apprunner"
$InfraDirFE  = Join-Path $InfraDir "frontend"

foreach ($p in @($InfraDirFE,$InfraDirAR,$InfraDirECR)) {
  if (-not (Test-Path $p)) { throw "Folder not found: $p" }
}

# --- AWS info ---
$AwsAccountId = (aws sts get-caller-identity --query "Account" --output text)
if (-not $AwsAccountId) { throw "Could not determine AWS Account ID (check AWS CLI credentials/profile)." }

$EcrHost = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
$EcrRepo = $ProjectName
$EcrUrl  = "$EcrHost/$EcrRepo"

# --- Confirm unless -AutoApprove ---
if (-not $AutoApprove) {
  $ans = Read-Host "This will destroy Frontend (S3+CloudFront), App Runner, and ECR for '$ProjectName' in $AwsRegion. Proceed? (y/N)"
  if ($ans -notin @("y","Y")) {
    Write-Host "Aborted." -ForegroundColor Cyan
    exit 0
  }
}

function Tf-Destroy($dir, [string[]]$vars) {
  Write-Host "`n=== Terraform destroy: $dir ===" -ForegroundColor Red
  terraform -chdir="$dir" init -upgrade | Out-Null
  $args = @("destroy") + $vars
  if ($AutoApprove) { $args += "-auto-approve" }
  terraform -chdir="$dir" @args
}

function Get-CommonVars() {
  @(
    "-var=project_name=$ProjectName",
    "-var=aws_region=$AwsRegion"
  )
}

# 1) Destroy Frontend (CloudFront + OAC + S3)
$feVars = (Get-CommonVars) + @(
  "-var=frontend_domain_name=",
  "-var=frontend_acm_certificate_arn="
)
Tf-Destroy -dir $InfraDirFE -vars $feVars

# 2) Destroy App Runner (service + IAM role)
$arVars = (Get-CommonVars) + @(
  "-var=ecr_repo_name=$EcrRepo",
  "-var=image_tag=$ImageTag"
)
Tf-Destroy -dir $InfraDirAR -vars $arVars

# 3) Optionally empty ECR repository (images), then destroy ECR
if ($ForceDeleteImages) {
  Write-Host "`n=== ECR: deleting images in $EcrRepo (optional) ===" -ForegroundColor Yellow
  try {
    $imageIds = aws ecr list-images --region $AwsRegion --repository-name $EcrRepo --query "imageIds" --output json | ConvertFrom-Json
  } catch {
    throw "Failed to list ECR images for $EcrRepo. $_"
  }

  if ($imageIds -and $imageIds.Count -gt 0) {
    $tmp = Join-Path $env:TEMP ("ecr-images-" + [guid]::NewGuid().ToString() + ".json")
    try {
      $imageIds | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
      aws ecr batch-delete-image --region $AwsRegion --repository-name $EcrRepo --image-ids "file://$tmp" | Out-Null
      Write-Host "Deleted $($imageIds.Count) image(s) from $EcrRepo"
    } finally {
      Remove-Item $tmp -ErrorAction SilentlyContinue
    }
  } else {
    Write-Host "No images found in $EcrRepo"
  }
} else {
  Write-Host "`nSkipping ECR image deletion. If the next step fails due to a non-empty repo, re-run with -ForceDeleteImages." -ForegroundColor DarkYellow
}

$ecrVars = (Get-CommonVars) + @(
  "-var=ecr_repo_name=$EcrRepo",
  "-var=image_tag=$ImageTag"
)
Tf-Destroy -dir $InfraDirECR -vars $ecrVars

Write-Host "`nAll resources destroyed for $ProjectName ($Environment)." -ForegroundColor Green
