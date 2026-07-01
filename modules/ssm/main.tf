# ============================================================================
# SSM Parameter Store
# ============================================================================
# 시크릿은 두 곳으로 나뉩니다.
#
# [bootstrap] 인프라를 destroy해도 살아남는 시크릿
#   - .terraform/bootstrap/main.tf 에서 관리
#   - 이 파일에서는 data 소스로 읽어옵니다.
#
# [메인 스택] 인프라와 수명이 같은 값
#   - db/password, kafka/private-ip, kafka/quorum-voters

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.environment}/db/password"
  type  = "SecureString"
  value = var.db_password
}

# ---- Bootstrap 시크릿 읽기 ----
# bootstrap/main.tf의 secret_keys 목록과 1:1로 대응합니다.
# 새 시크릿을 추가할 때는 bootstrap/main.tf의 secret_keys만 수정하고,
# 이 목록도 동일하게 맞춰 줍니다.
# ECS 태스크 정의가 참조하지 않는 키(monitoring/*, langfuse/* 등)는
# secret_arns 맵에는 포함되지만 ECS에 주입되지 않으므로 영향이 없습니다.

locals {
  app_secret_paths = {
    "keycloak-client-secret"         = "/${var.project}/${var.environment}/keycloak/client-secret"
    "keycloak-admin-password"        = "/${var.project}/${var.environment}/keycloak/admin-password"
    "manager-key"                    = "/${var.project}/${var.environment}/user/manager-key"
    "master-key"                     = "/${var.project}/${var.environment}/user/master-key"
    "toss-client-key"                = "/${var.project}/${var.environment}/toss/client-key"
    "toss-secret-key"                = "/${var.project}/${var.environment}/toss/secret-key"
    "slack-webhook-url"              = "/${var.project}/${var.environment}/slack/webhook-url"
    "slack-bot-token"                = "/${var.project}/${var.environment}/slack/bot-token"
    "gemini-api-key"                 = "/${var.project}/${var.environment}/ai/gemini-api-key"
    "kafka-cluster-id"               = "/${var.project}/${var.environment}/kafka/cluster-id"
    "monitoring-grafana-password"    = "/${var.project}/${var.environment}/monitoring/grafana-admin-password"
    "monitoring-slack-webhook-url"   = "/${var.project}/${var.environment}/monitoring/slack-webhook-url"
    "langfuse-nextauth-secret"       = "/${var.project}/${var.environment}/langfuse/nextauth-secret"
    "langfuse-salt"                  = "/${var.project}/${var.environment}/langfuse/salt"
  }
}

data "aws_ssm_parameter" "app_secrets" {
  for_each = local.app_secret_paths
  name     = each.value
}

locals {
  secret_arns = merge(
    { "db-password" = aws_ssm_parameter.db_password.arn },
    { for k, v in data.aws_ssm_parameter.app_secrets : k => v.arn },
  )
}

# ---- 메인 스택: Kafka / EC2 관련 파라미터 ----

# Kafka EC2 사설 IP (3대 리스트): Terraform이 인스턴스를 만들면서 자동으로 채웁니다.
resource "aws_ssm_parameter" "kafka_private_ip" {
  name  = "/${var.project}/${var.environment}/kafka/private-ip"
  type  = "String"
  value = var.kafka_private_ips
}

# Kafka Quorum 투표자 리스트 (3대): 브로커 간 클러스터 구성용
resource "aws_ssm_parameter" "kafka_quorum_voters" {
  name  = "/${var.project}/${var.environment}/kafka/quorum-voters"
  type  = "String"
  value = var.kafka_quorum_voters
}
