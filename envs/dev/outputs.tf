# ============================================================================
# 출력값(outputs): apply가 끝나면 화면에 보여줄 중요한 주소/정보
# ============================================================================

output "alb_dns_name" {
  description = "서비스 접속 주소 (ALB 기본 DNS)"
  value       = module.edge.alb_dns_name
}

output "ecr_repository_urls" {
  description = "서비스별 ECR 저장소 주소 (GitHub Actions가 여기로 push)"
  value       = module.ecs.ecr_repository_urls
}

output "rds_endpoint" {
  description = "RDS 접속 주소 (host:port)"
  value       = module.data.rds_endpoint
}

output "redis_endpoint" {
  description = "Redis 접속 주소"
  value       = module.data.redis_address
}

output "kafka_public_ips" {
  description = "Kafka EC2 공인 IP 목록 (SSH/관리용)"
  value       = module.compute_ec2.kafka_public_ips
}

output "kafka_private_ips" {
  description = "Kafka EC2 사설 IP 목록 (앱이 접속하는 주소)"
  value       = module.compute_ec2.kafka_private_ips
}

output "monitoring_public_ip" {
  description = "모니터링 EC2 공인 IP"
  value       = module.compute_ec2.monitoring_public_ip
}

output "grafana_url" {
  description = "Grafana 접속 주소"
  value       = "http://${module.compute_ec2.monitoring_public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus 접속 주소"
  value       = "http://${module.compute_ec2.monitoring_public_ip}:9090"
}

output "ecs_cluster_name" {
  description = "ECS 클러스터 이름 (배포 명령에 사용)"
  value       = module.ecs.cluster_name
}

output "github_actions_role_arn" {
  description = "GitHub Actions가 assume할 역할 ARN"
  value       = module.iam.github_actions_role_arn != null ? module.iam.github_actions_role_arn : "(disabled)"
}
