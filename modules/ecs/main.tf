# ============================================================================
# ECR: 도커 이미지 저장소
# ============================================================================

locals {
  ecr_repos = toset(concat(keys(local.services), ["bid-service"]))
}

resource "aws_ecr_repository" "app" {
  for_each = local.ecr_repos

  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ============================================================================
# ECS 클러스터 + 서비스 디스커버리(Cloud Map)
# ============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # base=N: 최소 N개를 On-Demand로 보장. desired_count <= base이면 Spot이 쓰이지 않음
  # weight=0: 해당 provider로 태스크를 배치하지 않음 (dev FARGATE=0으로 100% Spot 달성)
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = var.fargate_on_demand_base
    weight            = var.fargate_on_demand_weight
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = var.fargate_spot_weight
  }
}

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = var.service_namespace
  vpc         = var.vpc_id
  description = "internal service discovery for ${var.name}"
}

# ============================================================================
# 서비스 정의표 + 공통 환경변수 (locals)
# ============================================================================

locals {
  keycloak_url = "http://keycloak.${var.service_namespace}:18080"

  common_env = {
    TZ                                        = "Asia/Seoul"
    SPRING_PROFILES_ACTIVE                    = var.spring_profile
    SPRING_CLOUD_CONFIG_URI                   = "http://config-server.${var.service_namespace}:8888"
    EUREKA_CLIENT_SERVICEURL_DEFAULTZONE      = "http://discovery-server.${var.service_namespace}:8761/eureka/"
    MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE = "health,info,prometheus"
    LOKI_URL                                  = "http://${var.monitoring_private_ip}:3100"
  }

  services = {
    "config-server" = {
      port    = 8888, cpu = 512, memory = 1024
      schema  = null, redis = false, kafka = false, alb = false
      secrets = {}, extra_env = { SPRING_PROFILES_ACTIVE = "prod,native" }
    }
    "discovery-server" = {
      port      = 8761, cpu = 512, memory = 1024
      schema    = null, redis = false, kafka = false, alb = false
      secrets   = {}
      extra_env = { EUREKA_CLIENT_SERVICEURL_DEFAULTZONE = "http://discovery-server.${var.service_namespace}:8761/eureka/" }
    }
    "gateway-server" = {
      port    = 8000, cpu = 512, memory = 1024
      schema  = null, redis = false, kafka = false, alb = true
      secrets = {}
      extra_env = {
        SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUERURI = "${local.keycloak_url}/realms/${var.keycloak_realm}"
        SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWKSETURI = "${local.keycloak_url}/realms/${var.keycloak_realm}/protocol/openid-connect/certs"
      }
    }
    "user-service" = {
      port   = 19091, cpu = 2048, memory = 4096
      schema = "user_schema", redis = true, kafka = false, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        KEYCLOAK_CLIENT_SECRET     = "keycloak-client-secret"
        MANAGER_KEY                = "manager-key"
        MASTER_KEY                 = "master-key"
      }
      extra_env = {
        KEYCLOAK_SERVER_URL                                 = local.keycloak_url
        KEYCLOAK_REALM                                      = var.keycloak_realm
        SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUERURI = "${local.keycloak_url}/realms/${var.keycloak_realm}"
        SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWKSETURI = "${local.keycloak_url}/realms/${var.keycloak_realm}/protocol/openid-connect/certs"
      }
    }
    "auction-service" = {
      port      = 19092, cpu = 2048, memory = 4096
      schema    = "auction_schema", redis = false, kafka = true, alb = false
      secrets   = { SPRING_DATASOURCE_PASSWORD = "db-password" }
      extra_env = {}
    }
    "order-service" = {
      port      = 19094, cpu = 2048, memory = 4096
      schema    = "order_schema", redis = false, kafka = true, alb = false
      secrets   = { SPRING_DATASOURCE_PASSWORD = "db-password" }
      extra_env = {}
    }
    "payment-service" = {
      port   = 19095, cpu = 2048, memory = 4096
      schema = "payment_schema", redis = true, kafka = true, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        TOSS_PAYMENTS_CLIENT_KEY   = "toss-client-key"
        TOSS_PAYMENTS_SECRET_KEY   = "toss-secret-key"
      }
      extra_env = {}
    }
    "notification-service" = {
      port   = 19096, cpu = 2048, memory = 4096
      schema = "notification_schema", redis = true, kafka = true, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        SLACK_WEBHOOK_URL          = "slack-webhook-url"
        SLACK_BOT_TOKEN            = "slack-bot-token"
      }
      extra_env = {}
    }
    "ai-service" = {
      port   = 19097, cpu = 2048, memory = 4096
      schema = "ai_schema", redis = false, kafka = false, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        GEMINI_API_KEY             = "gemini-api-key"
      }
      extra_env = {}
    }
  }

  service_env = {
    for svc_name, s in local.services : svc_name => merge(
      local.common_env,
      s.schema == null ? {} : {
        SPRING_DATASOURCE_URL      = "jdbc:postgresql://${var.rds_address}:5432/${var.db_name}?currentSchema=${s.schema}"
        SPRING_DATASOURCE_USERNAME = var.db_username
      },
      s.redis ? { SPRING_DATA_REDIS_HOST = var.redis_address } : {},
      s.kafka ? { SPRING_KAFKA_BOOTSTRAPSERVERS = var.kafka_bootstrap_servers } : {},
      s.extra_env,
    )
  }
}

# ============================================================================
# ECS 일반 서비스 9개 (config, discovery, gateway, user, auction, order, payment, notification, ai)
# ============================================================================

resource "aws_cloudwatch_log_group" "app" {
  for_each          = local.services
  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = 14
}

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

resource "aws_ecs_task_definition" "app" {
  for_each = local.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${aws_ecr_repository.app[each.key].repository_url}:${var.container_image_tag}"
    essential = true

    portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]

    environment = [for k, v in local.service_env[each.key] : { name = k, value = tostring(v) }]

    secrets = [for env_name, key in each.value.secrets : { name = env_name, valueFrom = var.secret_arns[key] }]

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

resource "aws_ecs_service" "app" {
  for_each = local.services

  name            = each.key
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = var.fargate_on_demand_base
    weight            = var.fargate_on_demand_weight
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = var.fargate_spot_weight
  }

  health_check_grace_period_seconds = each.value.alb ? 180 : null

  network_configuration {
    subnets          = [var.primary_public_subnet_id]
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app[each.key].arn
  }

  dynamic "load_balancer" {
    for_each = each.value.alb ? [1] : []
    content {
      target_group_arn = var.target_group_gateway_arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

# ============================================================================
# 입찰(bid) 서비스 + Auto Scaling
# ============================================================================

locals {
  bid_port = 19093

  bid_env = merge(
    local.common_env,
    {
      SPRING_DATASOURCE_URL         = "jdbc:postgresql://${var.rds_address}:5432/${var.db_name}?currentSchema=bid_schema"
      SPRING_DATASOURCE_USERNAME    = var.db_username
      SPRING_DATA_REDIS_HOST        = var.redis_address
      SPRING_KAFKA_BOOTSTRAPSERVERS = var.kafka_bootstrap_servers
    },
  )
}

resource "aws_cloudwatch_log_group" "bid" {
  name              = "/ecs/${var.name}/bid-service"
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
  family                   = "${var.name}-bid-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "2048"
  memory                   = "8192"
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = "bid-service"
    image        = "${aws_ecr_repository.app["bid-service"].repository_url}:${var.container_image_tag}"
    essential    = true
    portMappings = [{ containerPort = local.bid_port, protocol = "tcp" }]
    environment  = [for k, v in local.bid_env : { name = k, value = tostring(v) }]
    secrets      = [{ name = "SPRING_DATASOURCE_PASSWORD", valueFrom = var.secret_arns["db-password"] }]
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
    subnets          = [var.primary_public_subnet_id]
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.bid.arn
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

resource "aws_appautoscaling_target" "bid" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.bid.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.bid_min_capacity
  max_capacity       = var.bid_max_capacity
}

resource "aws_appautoscaling_policy" "bid_cpu" {
  name               = "${var.name}-bid-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.bid.service_namespace
  resource_id        = aws_appautoscaling_target.bid.resource_id
  scalable_dimension = aws_appautoscaling_target.bid.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.bid_cpu_target

    # WebSocket 장기 연결 보호: scale-out은 빠르게(60s), scale-in은 보수적으로(300s)
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}

# cron은 UTC 기준. KST = UTC + 9시간
resource "aws_appautoscaling_scheduled_action" "bid_peak_up" {
  name               = "${var.name}-bid-peak-up"
  service_namespace  = aws_appautoscaling_target.bid.service_namespace
  resource_id        = aws_appautoscaling_target.bid.resource_id
  scalable_dimension = aws_appautoscaling_target.bid.scalable_dimension
  schedule           = "cron(50 14 * * ? *)"

  scalable_target_action {
    min_capacity = 4
    max_capacity = var.bid_max_capacity
  }
}

resource "aws_appautoscaling_scheduled_action" "bid_peak_down" {
  name               = "${var.name}-bid-peak-down"
  service_namespace  = aws_appautoscaling_target.bid.service_namespace
  resource_id        = aws_appautoscaling_target.bid.resource_id
  scalable_dimension = aws_appautoscaling_target.bid.scalable_dimension
  schedule           = "cron(30 15 * * ? *)"

  scalable_target_action {
    min_capacity = var.bid_min_capacity
    max_capacity = var.bid_max_capacity
  }
}

# ============================================================================
# Keycloak (인증 서버)
# ============================================================================

resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/${var.name}/keycloak"
  retention_in_days = 14
}

resource "aws_service_discovery_service" "keycloak" {
  name = "keycloak"
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

resource "aws_ecs_task_definition" "keycloak" {
  family                   = "${var.name}-keycloak"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = "keycloak"
    image     = "quay.io/keycloak/keycloak:25.0"
    essential = true
    command   = ["start-dev", "--http-port=18080"]

    portMappings = [{ containerPort = 18080, protocol = "tcp" }]

    environment = [
      { name = "KEYCLOAK_ADMIN", value = "admin" },
      { name = "KC_DB", value = "postgres" },
      { name = "KC_DB_URL", value = "jdbc:postgresql://${var.rds_address}:5432/${var.db_name}" },
      { name = "KC_DB_USERNAME", value = var.db_username },
      { name = "KC_DB_SCHEMA", value = "keycloak_schema" },
      { name = "KC_HEALTH_ENABLED", value = "true" },
      { name = "KC_HOSTNAME_STRICT", value = "false" },
    ]

    secrets = [
      { name = "KC_DB_PASSWORD", valueFrom = var.secret_arns["db-password"] },
      { name = "KEYCLOAK_ADMIN_PASSWORD", valueFrom = var.secret_arns["keycloak-admin-password"] },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.keycloak.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "keycloak" {
  name            = "keycloak"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.primary_public_subnet_id]
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.keycloak.arn
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [desired_count]
  }
}
