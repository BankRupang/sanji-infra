# ============================================================================
# 입찰(bid) 서비스 + Auto Scaling
# ============================================================================
# bid만 Auto Scaling 대상. 2~6 태스크, CPU 목표 추적.
# bid는 ALB에 직접 붙지 않고, gateway가 STOMP(WebSocket)를 내부로 중계합니다.

locals {
  bid_port = 19093

  bid_env = merge(
    local.common_env,
    {
      SPRING_DATASOURCE_URL         = "jdbc:postgresql://${aws_db_instance.main.address}:5432/${var.db_name}?currentSchema=bid_schema"
      SPRING_DATASOURCE_USERNAME    = var.db_username
      SPRING_DATA_REDIS_HOST        = aws_elasticache_cluster.redis.cache_nodes[0].address
      SPRING_KAFKA_BOOTSTRAPSERVERS = "${aws_instance.kafka.private_ip}:9092"
    },
  )
}

resource "aws_cloudwatch_log_group" "bid" {
  name              = "/ecs/${local.name}/bid-service"
  retention_in_days = 14
}

resource "aws_service_discovery_service" "bid" {
  name = "bid-service"
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

resource "aws_ecs_task_definition" "bid" {
  family                   = "${local.name}-bid-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "2048" # 2 vCPU
  memory                   = "8192" # 8GB
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name         = "bid-service"
    image        = "${aws_ecr_repository.app["bid-service"].repository_url}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = local.bid_port, protocol = "tcp" }]
    environment  = [for k, v in local.bid_env : { name = k, value = tostring(v) }]
    secrets      = [{ name = "SPRING_DATASOURCE_PASSWORD", valueFrom = local.secret_arns["db-password"] }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.bid.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "bid" {
  name            = "bid-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bid.arn
  desired_count   = var.bid_min_capacity
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [local.primary_public_subnet_id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.bid.arn
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    # 오토스케일링이 desired_count를 조정하므로 Terraform은 건드리지 않음
    ignore_changes = [desired_count]
  }
}

# ----------------------------------------------------------------------------
# Auto Scaling
# ----------------------------------------------------------------------------

# 스케일 대상 등록: bid 서비스의 desired_count를 2~6 사이로 조절
resource "aws_appautoscaling_target" "bid" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.bid.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.bid_min_capacity
  max_capacity       = var.bid_max_capacity
}

# 목표 추적(Target Tracking): 평균 CPU를 목표치 근처로 유지
resource "aws_appautoscaling_policy" "bid_cpu" {
  name               = "${local.name}-bid-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.bid.service_namespace
  resource_id        = aws_appautoscaling_target.bid.resource_id
  scalable_dimension = aws_appautoscaling_target.bid.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.bid_cpu_target # 60%

    # WebSocket 장기 연결 보호: scale-out은 빠르게(60s), scale-in은 보수적으로(300s)
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}

# ----------------------------------------------------------------------------
# 예약(Scheduled) 스케일링 - 보조 수단
# ----------------------------------------------------------------------------
# 주의: 경매 마감 시각은 Anti-Sniping으로 계속 밀릴 수 있어 고정 예약만으로는 부족합니다.
# 그래서 목표 추적이 "기본", 아래 예약은 "마감이 한 시간대에 몰릴 때만" 쓰는 보조입니다.
# 아래 시각은 예시(자정 KST 부근)이며, 실제 운영 패턴에 맞게 조정하세요.
# cron은 UTC 기준입니다. 한국시간(KST) = UTC + 9시간.

# 마감 10분 전 느낌으로 최소 태스크를 4로 올림 (예: 23:50 KST = 14:50 UTC)
resource "aws_appautoscaling_scheduled_action" "bid_peak_up" {
  name               = "${local.name}-bid-peak-up"
  service_namespace  = aws_appautoscaling_target.bid.service_namespace
  resource_id        = aws_appautoscaling_target.bid.resource_id
  scalable_dimension = aws_appautoscaling_target.bid.scalable_dimension
  schedule           = "cron(50 14 * * ? *)"

  scalable_target_action {
    min_capacity = 4
    max_capacity = var.bid_max_capacity
  }
}

# 마감 후 최소 태스크를 2로 원복 (예: 00:30 KST = 15:30 UTC)
resource "aws_appautoscaling_scheduled_action" "bid_peak_down" {
  name               = "${local.name}-bid-peak-down"
  service_namespace  = aws_appautoscaling_target.bid.service_namespace
  resource_id        = aws_appautoscaling_target.bid.resource_id
  scalable_dimension = aws_appautoscaling_target.bid.scalable_dimension
  schedule           = "cron(30 15 * * ? *)"

  scalable_target_action {
    min_capacity = var.bid_min_capacity
    max_capacity = var.bid_max_capacity
  }
}
