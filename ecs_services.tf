# ============================================================================
# ECS 일반 서비스 (config, discovery, gateway, user, auction, order, payment,
#                  notification, ai) - 총 9개를 한 번에 생성
# ============================================================================
# locals.tf 의 services 표를 for_each로 돌면서 서비스마다
#   로그 그룹 + 서비스 디스커버리 + 태스크 정의 + ECS 서비스
# 네 가지를 똑같은 모양으로 찍어냅니다.
# (bid는 오토스케일링, keycloak은 다른 이미지라 각각 별도 파일에서 다룹니다)

# 서비스별 최종 환경변수 계산.
# RDS 주소, Redis 주소, Kafka IP는 그 자원이 만들어진 뒤에야 정해지므로 여기서 조합합니다.
locals {
  service_env = {
    for name, s in local.services : name => merge(
      local.common_env,
      # DB를 쓰는 서비스면 데이터소스 주소를 넣음 (스키마로 서비스별 분리)
      s.schema == null ? {} : {
        SPRING_DATASOURCE_URL      = "jdbc:postgresql://${aws_db_instance.main.address}:5432/${var.db_name}?currentSchema=${s.schema}"
        SPRING_DATASOURCE_USERNAME = var.db_username
      },
      # Redis를 쓰는 서비스
      s.redis ? { SPRING_DATA_REDIS_HOST = aws_elasticache_cluster.redis.cache_nodes[0].address } : {},
      # Kafka를 쓰는 서비스
      s.kafka ? { SPRING_KAFKA_BOOTSTRAPSERVERS = "${aws_instance.kafka.private_ip}:9092" } : {},
      # 서비스 고유 환경변수 (맨 뒤라 위 값을 덮어쓸 수 있음)
      s.extra_env,
    )
  }
}

# 서비스별 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "app" {
  for_each          = local.services
  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = 14
}

# 서비스별 서비스 디스커버리 등록 (sanji.local 안의 DNS 이름)
resource "aws_service_discovery_service" "app" {
  for_each = local.services
  name     = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# 태스크 정의: "이 컨테이너를 어떻게 띄울지" 설계도
resource "aws_ecs_task_definition" "app" {
  for_each = local.services

  family                   = "${local.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${aws_ecr_repository.app[each.key].repository_url}:${var.container_image_tag}"
    essential = true

    portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]

    # 일반 환경변수 (map -> ECS가 원하는 [{name, value}] 형태로 변환)
    environment = [for k, v in local.service_env[each.key] : { name = k, value = tostring(v) }]

    # 시크릿: SSM 값을 컨테이너 환경변수로 자동 주입
    secrets = [for env_name, key in each.value.secrets : { name = env_name, valueFrom = local.secret_arns[key] }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app[each.key].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ECS 서비스: 태스크를 몇 개 띄우고 어디에 연결할지
resource "aws_ecs_service" "app" {
  for_each = local.services

  name            = each.key
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # ALB에 붙는 gateway는 기동 시간이 걸리므로 헬스체크 유예시간을 줍니다.
  health_check_grace_period_seconds = each.value.alb ? 180 : null

  network_configuration {
    subnets          = [local.primary_public_subnet_id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # NAT 없이 ECR/외부 API로 나가려면 공인 IP 필요
  }

  # 서비스 디스커버리 등록
  service_registries {
    registry_arn = aws_service_discovery_service.app[each.key].arn
  }

  # gateway만 ALB 대상 그룹에 연결
  dynamic "load_balancer" {
    for_each = each.value.alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.gateway.arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  # 롤링 배포: 새 태스크가 정상이 된 뒤 옛 태스크를 내림
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    # desired_count를 사람이 바꾸거나 오토스케일이 조정해도 Terraform이 되돌리지 않게
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
