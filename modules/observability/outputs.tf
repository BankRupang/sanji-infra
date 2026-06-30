output "sns_topic_arn" {
  description = "경보 알림 SNS 주제 ARN. alert_email이 없으면 빈 문자열"
  value       = var.alert_email != "" ? aws_sns_topic.alerts[0].arn : ""
}
