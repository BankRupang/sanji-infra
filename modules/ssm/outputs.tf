output "secret_arns" {
  description = "ECS 태스크에 주입할 시크릿 ARN 맵"
  value       = local.secret_arns
}

output "db_password_arn" {
  value = aws_ssm_parameter.db_password.arn
}
