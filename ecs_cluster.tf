# ============================================================================
# ECS 클러스터 + 서비스 디스커버리(Cloud Map)
# ============================================================================
# stateless 서비스(App, Bid)는 ECS Fargate로 운영합니다.
# 서비스끼리 서로를 찾는 방법으로 Cloud Map(사설 DNS)을 씁니다.
#   예: gateway가 "config-server.sanji.local:8888" 이름으로 config 서버를 찾음.

resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"

  # 클러스터 단위 지표/로그를 더 자세히 보고 싶을 때 (CloudWatch Container Insights)
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Fargate 사용 선언. 평소엔 FARGATE, 비용 절감이 필요하면 SPOT도 섞을 수 있습니다.
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# 사설 DNS 네임스페이스. 이 안에서 "서비스이름.sanji.local" 주소가 만들어집니다.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = var.service_namespace
  vpc         = aws_vpc.main.id
  description = "internal service discovery for ${local.name}"
}
