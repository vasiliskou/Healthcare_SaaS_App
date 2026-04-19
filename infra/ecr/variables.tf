variable "project_name" {
  description = "Short name used to prefix resources"
  type        = string
  default     = "consultation-app"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "consultation-app"
}

# Image tag you will push (e.g., latest)
variable "image_tag" {
  description = "Image tag to deploy from ECR (you will push this tag)"
  type        = string
  default     = "latest"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
