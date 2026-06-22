# ============================================================================
# 공통 계산값(locals)과 서비스 정의표
# ============================================================================
# locals는 "여러 곳에서 반복해 쓰는 값"을 한 번 정의해두는 곳입니다.

locals {
  # 모든 리소스 이름 앞에 붙일 접두사. 예: "sanji-prod"
  name = "${var.project}-${var.environment}"

  # primary_az 한 곳에만 ECS/EC2를 띄우므로, 그 AZ의 서브넷 정보를 자주 씁니다.
  primary_public_subnet_id  = aws_subnet.public[var.primary_az].id
  primary_private_subnet_id = aws_subnet.private[var.primary_az].id

  # --------------------------------------------------------------------------
  # ECS로 띄울 "일반 Spring 서비스" 정의표
  # --------------------------------------------------------------------------
  # bid(오토스케일링)와 keycloak(다른 이미지)은 성격이 달라서
  # 각각 ecs_bid.tf, ecs_keycloak.tf 에서 따로 다룹니다.
  #
  # 표 한 줄이 서비스 하나입니다. for_each로 이 표를 한 바퀴 돌며
  # 태스크 정의 + 서비스 + 로그 그룹 + 서비스 디스커버리를 한꺼번에 만듭니다.
  # 새 서비스가 생기면 여기 한 줄만 추가하면 됩니다.
  #
  # 각 칸의 뜻:
  #   port         : 컨테이너가 여는 포트
  #   cpu / memory : Fargate 사양 (cpu 1024 = 1 vCPU)
  #   schema       : DB 스키마 이름. null이면 DB를 안 씀
  #   redis        : Redis가 필요하면 true
  #   kafka        : Kafka가 필요하면 true
  #   alb          : ALB(외부 진입점)에 연결할지 여부. gateway만 true
  #   secrets      : {컨테이너_환경변수_이름 = SSM_시크릿_키} 형태. ssm.tf의 키와 맞춰야 함
  #   extra_env    : 이 서비스에만 추가로 넣을 환경변수
  services = {
    "config-server" = {
      port    = 8888, cpu = 512, memory = 1024
      schema  = null, redis = false, kafka = false, alb = false
      secrets = {}, extra_env = {}
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
      port   = 19091, cpu = 1024, memory = 2048
      schema = "user_schema", redis = false, kafka = false, alb = false
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
      port      = 19092, cpu = 1024, memory = 2048
      schema    = "auction_schema", redis = true, kafka = true, alb = false
      secrets   = { SPRING_DATASOURCE_PASSWORD = "db-password" }
      extra_env = {}
    }
    "order-service" = {
      port      = 19094, cpu = 1024, memory = 2048
      schema    = "order_schema", redis = false, kafka = true, alb = false
      secrets   = { SPRING_DATASOURCE_PASSWORD = "db-password" }
      extra_env = {}
    }
    "payment-service" = {
      port   = 19095, cpu = 1024, memory = 2048
      schema = "payment_schema", redis = false, kafka = true, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        TOSS_CLIENT_KEY            = "toss-client-key"
        TOSS_SECRET_KEY            = "toss-secret-key"
      }
      extra_env = {}
    }
    "notification-service" = {
      port   = 19096, cpu = 1024, memory = 2048
      schema = "notification_schema", redis = false, kafka = true, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        SLACK_WEBHOOK_URL          = "slack-webhook-url"
        SLACK_BOT_TOKEN            = "slack-bot-token"
      }
      extra_env = {}
    }
    "ai-service" = {
      port   = 19097, cpu = 1024, memory = 2048
      schema = "ai_schema", redis = false, kafka = false, alb = false
      secrets = {
        SPRING_DATASOURCE_PASSWORD = "db-password"
        GEMINI_API_KEY             = "gemini-api-key"
      }
      extra_env = {}
    }
  }

  # Keycloak 내부 주소 (서비스 디스커버리 DNS). gateway, user-service가 토큰 검증에 사용.
  keycloak_url = "http://keycloak.${var.service_namespace}:18080"

  # 모든 서비스에 공통으로 들어가는 환경변수.
  # 일부 값은 RDS/Redis/EC2가 만들어진 뒤에야 정해지므로 그 리소스를 참조합니다.
  common_env = {
    SPRING_PROFILES_ACTIVE                    = var.spring_profile
    SPRING_CLOUD_CONFIG_URI                   = "http://config-server.${var.service_namespace}:8888"
    EUREKA_CLIENT_SERVICEURL_DEFAULTZONE      = "http://discovery-server.${var.service_namespace}:8761/eureka/"
    MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE = "health,info,prometheus"
    # 로그는 모니터링 EC2의 Loki로 보냅니다.
    LOKI_URL = "http://${aws_instance.monitoring.private_ip}:3100"
  }
}
