<#
.SYNOPSIS
  Creates Terraform backend resources (S3 bucket + DynamoDB table) for remote state.
#>

param(
  [string]$Region = "eu-west-3",
  [string]$LockTableName = "tf-locks"
)

# Stop on errors
$ErrorActionPreference = "Stop"

Write-Host "`n=== Initializing Terraform backend (S3 + DynamoDB) ===" -ForegroundColor Yellow

# --- Determine AWS account ---
$AccountId = aws sts get-caller-identity --query "Account" --output text
if (-not $AccountId) {
  throw "Could not determine AWS Account ID. Check your AWS CLI credentials."
}

# --- Bucket and table names ---
$TfStateBucket = "tf-state-$AccountId-$Region"

Write-Host "Using bucket: $TfStateBucket"
Write-Host "Using lock table: $LockTableName"
Write-Host "Region: $Region"

# --- Create S3 bucket ---
try {
  Write-Host "`nCreating S3 bucket (if not exists)..." -ForegroundColor Cyan
  $exists = aws s3api head-bucket --bucket $TfStateBucket 2>$null
  if ($LASTEXITCODE -ne 0) {
    aws s3api create-bucket `
      --bucket $TfStateBucket `
      --region $Region `
      --create-bucket-configuration LocationConstraint=$Region | Out-Null
    Write-Host " Bucket created: $TfStateBucket"
  } else {
    Write-Host "Bucket already exists — skipping creation."
  }
} catch {
  Write-Host "Error creating bucket (possibly already exists): $_" -ForegroundColor DarkYellow
}

# --- Enable versioning ---
Write-Host "Enabling versioning..."
aws s3api put-bucket-versioning `
  --bucket $TfStateBucket `
  --versioning-configuration Status=Enabled | Out-Null

# --- Enable default encryption ---
Write-Host "Enabling default AES256 encryption..."
aws s3api put-bucket-encryption `
  --bucket $TfStateBucket `
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' | Out-Null

# --- Create DynamoDB table for state lock ---
Write-Host "`nCreating DynamoDB table (if not exists)..." -ForegroundColor Cyan
try {
  $existing = aws dynamodb describe-table --table-name $LockTableName --region $Region 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Lock table already exists — skipping creation."
  } else {
    aws dynamodb create-table `
      --table-name $LockTableName `
      --attribute-definitions AttributeName=LockID,AttributeType=S `
      --key-schema AttributeName=LockID,KeyType=HASH `
      --billing-mode PAY_PER_REQUEST `
      --region $Region | Out-Null
    Write-Host " DynamoDB table created: $LockTableName"
  }
catch {
  Write-Host ("Error creating DynamoDB table (possibly already exists): {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
}

Write-Host "`n Terraform backend initialized successfully!" -ForegroundColor Green
Write-Host "S3 bucket: $TfStateBucket"
Write-Host "DynamoDB table: $LockTableName"
Write-Host "Region: $Region"
