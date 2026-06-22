# ============================================================================
# 출력값(outputs): apply가 끝나면 화면에 보여줄 중요한 주소/정보
# ============================================================================
# 배포 후 "어디로 접속하지?", "ECR 주소가 뭐지?"를 바로 확인할 수 있습니다.
# 보고 싶을 때: terraform output

output "alb_dns_name" {
  description = "서비스 접속 주소 (ALB 기본 DNS). 브라우저/클라이언트는 여기로 접속합니다."
  value       = aws_lb.main.dns_name
}

output "ecr_repository_urls" {
  description = "서비스별 ECR 저장소 주소 (GitHub Actions가 여기로 push)"
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "rds_endpoint" {
  description = "RDS 접속 주소 (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "redis_endpoint" {
  description = "Redis 접속 주소"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "kafka_public_ip" {
  description = "Kafka EC2 공인 IP (SSH/관리용)"
  value       = aws_instance.kafka.public_ip
}

output "kafka_private_ip" {
  description = "Kafka EC2 사설 IP (앱이 접속하는 주소). SSM에도 자동 등록됨"
  value       = aws_instance.kafka.private_ip
}

output "monitoring_public_ip" {
  description = "모니터링 EC2 공인 IP"
  value       = aws_instance.monitoring.public_ip
}

output "grafana_url" {
  description = "Grafana 접속 주소"
  value       = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus 접속 주소"
  value       = "http://${aws_instance.monitoring.public_ip}:9090"
}

output "ecs_cluster_name" {
  description = "ECS 클러스터 이름 (배포 명령에 사용)"
  value       = aws_ecs_cluster.main.name
}

output "github_actions_role_arn" {
  description = "GitHub Actions가 assume할 역할 ARN (CI/CD 워크플로우에 넣음)"
  value       = var.enable_github_oidc ? aws_iam_role.github_actions[0].arn : "(disabled)"
}
