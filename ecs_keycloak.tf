# ============================================================================
# Keycloak (인증 서버)
# ============================================================================
# Keycloak도 Fargate로 운영합니다.
# 공개 이미지를 쓰므로 ECR 저장소가 없고, DB는 같은 RDS의 keycloak_schema를 씁니다.
#
# 주의: 여기서는 빠른 기동을 위해 start-dev 모드로 둡니다.
# 운영 강화가 필요하면 realm을 구워 넣은 커스텀 이미지 + start(프로덕션) 모드로 전환하세요.

resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/${local.name}/keycloak"
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
  family                   = "${local.name}-keycloak"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "keycloak"
    image     = "quay.io/keycloak/keycloak:25.0"
    essential = true
    command   = ["start-dev", "--http-port=18080"]

    portMappings = [{ containerPort = 18080, protocol = "tcp" }]

    environment = [
      { name = "KEYCLOAK_ADMIN", value = "admin" },
      { name = "KC_DB", value = "postgres" },
      { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_db_instance.main.address}:5432/${var.db_name}" },
      { name = "KC_DB_USERNAME", value = var.db_username },
      { name = "KC_DB_SCHEMA", value = "keycloak_schema" },
      { name = "KC_HEALTH_ENABLED", value = "true" },
      { name = "KC_HOSTNAME_STRICT", value = "false" },
    ]

    secrets = [
      { name = "KC_DB_PASSWORD", valueFrom = local.secret_arns["db-password"] },
      { name = "KEYCLOAK_ADMIN_PASSWORD", valueFrom = local.secret_arns["keycloak-admin-password"] },
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
    subnets          = [local.primary_public_subnet_id]
    security_groups  = [aws_security_group.ecs.id]
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
