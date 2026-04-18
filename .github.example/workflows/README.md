# GitHub Actions Workflows

This directory contains GitHub Actions workflows for CI/CD automation.

## Setup: Required Secrets

Before using these workflows, you must configure the following **repository secrets** in GitHub:

1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** and add each of the following:

### Required Secrets

- `AWS_ACCESS_KEY_ID` — Your AWS access key ID  
- `AWS_SECRET_ACCESS_KEY` — Your AWS secret access key  
- `AWS_ACCOUNT_ID` — Your AWS account ID (e.g., `123456789012`)  
- `OPENAI_API_KEY` — Your OpenAI API key (starts with `sk-`)  
- `CLERK_SECRET_KEY` — Your Clerk secret key (`sk_live_...` for production, `sk_test_...` for development)  
- `CLERK_JWKS_URL` — Clerk JWKS URL (e.g., `https://your-instance.clerk.accounts.dev/.well-known/jwks.json`)  
- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` — Clerk publishable key (`pk_live_...` or `pk_test_...`)  

>  **Tip:** For improved security, consider using [GitHub OIDC authentication with AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html) instead of long-lived access keys.

---

### How to Get AWS Credentials (if not using OIDC)

1. Open **AWS Console → IAM → Users**
2. Create a new user or select an existing one
3. Attach a policy (temporary option): `PowerUserAccess`  
   *Or better, create a **custom least-privilege policy** with only required permissions.*
4. Create an **Access Key**, then copy both the **Access Key ID** and **Secret Access Key**

---

### Required AWS Permissions

The AWS user or role must have permissions for:

- **ECR** — Create repositories, push images  
- **App Runner** — Create and update services  
- **S3** — Create buckets and upload files  
- **CloudFront** — Create distributions and invalidate cache  
- **IAM** — Create roles for App Runner (and allow `iam:PassRole`)  
- **DynamoDB** — Manage Terraform lock table  
- **STS** — Retrieve caller identity (used for automation)  
- **Terraform state management** — S3 + DynamoDB access

>  **Simplified Option (Development Only):**  
> You can temporarily attach **full access** managed policies for faster setup:  
> - `AmazonEC2ContainerRegistryFullAccess`  
> - `AWSAppRunnerFullAccess`  
> - `AmazonS3FullAccess`  
> - `CloudFrontFullAccess`  
> - `AmazonDynamoDBFullAccess`  
> - `IAMFullAccess` *(only if your workflow creates or passes roles)*  
>
>  **Recommendation (Production):** Replace these with **least-privilege custom policies** granting only the required actions listed above.

---

## Workflow: Deploy to AWS

**File:** `.github/workflows/deploy.yml`

### Triggers

- **Automatic:** Runs on push to `main` or `production` branches  
- **Manual:** Can be triggered manually with environment selection

### What It Does

1.  Checks out code  
2.  Configures AWS credentials  
3.  Sets up Docker, Node.js, Python, and Terraform  
4.  Deploys backend — creates ECR repo, builds Docker image, pushes to ECR, and deploys App Runner  
5.  Deploys frontend — builds Next.js, uploads to S3, and triggers CloudFront invalidation  
6.  Displays deployment URLs in the workflow summary  

---

### Usage

#### Automatic Deployment

```bash
# Push to main branch (deploys to dev environment)
git push origin main
```

### Destroy AWS Infrastructure

**File:** `.github/workflows/destroy.yml`

