output "service_arn" {
  value = aws_apprunner_service.service.arn
}

output "service_status" {
  value = aws_apprunner_service.service.status
}

output "apprunner_service_url" {
  value       = "https://${replace(aws_apprunner_service.service.service_url, "https://", "")}"
  description = "Public HTTPS URL of your backend"
}
