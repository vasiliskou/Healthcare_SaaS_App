# Required
variable "project_name" {
  description = "Base project name (used in resource names)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for S3 (CloudFront is global)"
  type        = string
}

# Frontend deployment
variable "frontend_domain_name" {
  description = "Custom domain for CloudFront (leave empty to use default *.cloudfront.net)"
  type        = string
  default     = ""
}

variable "frontend_acm_certificate_arn" {
  description = "ACM cert ARN in us-east-1 for the custom domain; leave empty if not using custom domain"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
