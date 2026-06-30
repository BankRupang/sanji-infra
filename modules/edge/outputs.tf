output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_arn_suffix" {
  description = "CloudWatch 경보 dimensions 에 쓰는 ALB 축약 ARN"
  value       = aws_lb.main.arn_suffix
}

output "target_group_gateway_arn" {
  value = aws_lb_target_group.gateway.arn
}

output "http_listener_arn" {
  value = aws_lb_listener.http.arn
}
