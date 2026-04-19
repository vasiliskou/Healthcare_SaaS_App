locals {
  common_tags = {
    Project = var.project_name
    Managed = "Terraform"
  }
}

# Who am I?
data "aws_caller_identity" "current" {}

# Read existing ECR repository by name (created in the ECR stack)
data "aws_ecr_repository" "repo" {
  name = var.ecr_repo_name
}

# ---------- IAM for App Runner to pull ECR ----------
# Access role used by App Runner to authenticate to ECR
# For ECR pulls, the trust principal should be build.apprunner.amazonaws.com
data "aws_iam_policy_document" "apprunner_ecr_trust" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_ecr" {
  name               = "${var.project_name}-apprunner-ecr"
  assume_role_policy = data.aws_iam_policy_document.apprunner_ecr_trust.json
  tags               = local.common_tags
}

# Managed policy with least-priv ECR pull
resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  role       = aws_iam_role.apprunner_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# Build full image identifier: <acct>.dkr.ecr.<region>.amazonaws.com/repo:tag
locals {
  image_identifier = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${data.aws_ecr_repository.repo.name}:${var.image_tag}"
}

# Combine env vars (fixed + user-supplied)
locals {
  env_vars = merge(
    {
      OPENAI_API_KEY       = var.openai_api_key
      CLERK_SECRET_KEY     = var.clerk_secret_key
      CLERK_JWKS_URL       = var.clerk_jwks_url
      ALLOWED_CORS_ORIGINS = var.allowed_cors_origins
      ENV                  = "prod"
    },
    var.extra_env
  )
}

resource "aws_apprunner_auto_scaling_configuration_version" "basic" {
  auto_scaling_configuration_name = "${var.project_name}-asc"
  min_size                        = var.apprunner_min_size
  max_size                        = var.apprunner_max_size
  max_concurrency                 = var.apprunner_max_concurrency

  # Optional: keep the latest version when updating to avoid name collisions
  # lifecycle {
  #   create_before_destroy = true
  # }
  tags = local.common_tags
}


resource "aws_apprunner_service" "service" {
  service_name = "${var.project_name}-service"
  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.basic.arn

  # (keep your auto_scaling_configuration_arn here if you added it)

  source_configuration {
    auto_deployments_enabled = false

    image_repository {
      image_identifier      = local.image_identifier
      image_repository_type = "ECR"

      image_configuration {
        port = tostring(var.container_port)

        # provider expects map(string)
        runtime_environment_variables = local.env_vars
      }
    }

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_ecr.arn
    }
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = var.health_check_path
    interval            = 20
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  instance_configuration {
    cpu    = tostring(var.apprunner_cpu)
    memory = tostring(var.apprunner_memory)
  }

  tags = local.common_tags
}
