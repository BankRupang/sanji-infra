# ============================================================================
# ElastiCache: Redis (캐시 + Redisson 분산 락)
# ============================================================================
# Redis는 단순 캐시가 아니라 입찰 핵심 경로(Redisson 분산 락)에도 씁니다.
# t3.micro로 시작하고, 부하테스트에서 모자라면 변수만 바꿔 t3.medium으로 올립니다.

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name}-redis-subnet"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1 # 단일 노드 (문서: 단순 구성 우선)
  port                 = 6379
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # 단일 AZ 운영
  availability_zone = var.primary_az

  tags = { Name = "${local.name}-redis" }
}
