# Required meta
variable "project_name" {
  description = "Project/service base name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repo_name" {
  description = "Existing ECR repository name"
  type        = string
}

variable "image_tag" {
  description = "Image tag to deploy from ECR"
  type        = string
}

# App Runner sizing (0.25 vCPU / 0.5 GB)
# Valid cpu: 256, 512, 1024, 2048, 4096
# Valid memory (MB): 512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288
variable "apprunner_cpu" {
  description = "vCPU in units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "apprunner_memory" {
  description = "Memory in MB (512 = 0.5 GB)"
  type        = number
  default     = 512
}

# Networking/health
variable "container_port" {
  description = "Container port FastAPI listens on"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/health"
}

# Env vars for the service
variable "openai_api_key" {
  type        = string
  sensitive   = true
  description = "OpenAI API key (injected from env var)"
}

variable "clerk_secret_key" {
  type        = string
  sensitive   = true
  description = "Clerk secret key (injected from env var)"
}

variable "clerk_jwks_url" {
  type        = string
  description = "Clerk JWKS URL"
}

# Optional CORS (comma-separated list)
variable "allowed_cors_origins" {
  description = "Comma separated origins for CORS (optional)"
  type        = string
  default     = "http://localhost:3000,http://127.0.0.1:3000"
}

# Optional extra environment variables
variable "extra_env" {
  description = "Additional environment variables to inject"
  type        = map(string)
  default     = {}
}
# App Runner autoscaling (keeps it to 1 instance)
variable "apprunner_min_size" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "apprunner_max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 1
}

variable "apprunner_max_concurrency" {
  description = "Max concurrent requests per instance"
  type        = number
  default     = 10 # sensible default; adjust to your FastAPI capacity
}
