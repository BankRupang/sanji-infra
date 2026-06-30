output "rds_address" {
  description = "RDS 호스트 주소 (포트 제외)"
  value       = aws_db_instance.main.address
}

output "rds_endpoint" {
  description = "RDS 접속 주소 (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_identifier" {
  value = aws_db_instance.main.identifier
}

output "redis_address" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_cluster_id" {
  value = aws_elasticache_cluster.redis.cluster_id
}
