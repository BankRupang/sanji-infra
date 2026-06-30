# ============================================================================
# SSM Parameter Store
# ============================================================================
# 시크릿은 두 곳으로 나뉩니다.
#
# [bootstrap] 인프라를 destroy해도 살아남는 시크릿
#   - keycloak, toss, slack, gemini, grafana, langfuse, kafka/cluster-id
#   - .terraform/bootstrap/main.tf 에서 관리
#   - 이 파일에서는 data 소스로 읽어옵니다.
#
# [메인 스택] 인프라와 수명이 같은 값
#   - kafka/private-ip: EC2 인스턴스가 뜰 때 Terraform이 자동으로 채움

# DB 비밀번호: tfvars의 var.db_password 로 RDS를 만들고, 같은 값을 SSM에도 저장합니다.
# ECS 앱은 SSM 경로로 읽습니다. (bootstrap 대상 아님 - tfvars에 값이 남아있으므로)
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.environment}/db/password"
  type  = "SecureString"
  value = var.db_password
}

# ---- Bootstrap 시크릿 읽기 ----

locals {
  app_secret_paths = {
    "keycloak-client-secret"  = "/${var.project}/${var.environment}/keycloak/client-secret"
    "keycloak-admin-password" = "/${var.project}/${var.environment}/keycloak/admin-password"
    "manager-key"             = "/${var.project}/${var.environment}/user/manager-key"
    "master-key"              = "/${var.project}/${var.environment}/user/master-key"
    "toss-client-key"         = "/${var.project}/${var.environment}/toss/client-key"
    "toss-secret-key"         = "/${var.project}/${var.environment}/toss/secret-key"
    "slack-webhook-url"       = "/${var.project}/${var.environment}/slack/webhook-url"
    "slack-bot-token"         = "/${var.project}/${var.environment}/slack/bot-token"
    "gemini-api-key"          = "/${var.project}/${var.environment}/ai/gemini-api-key"
  }
}

data "aws_ssm_parameter" "app_secrets" {
  for_each = local.app_secret_paths
  name     = each.value
}


# ---- ECS 태스크 정의에서 "시크릿 키 -> SSM ARN" 조회표 ----

locals {
  secret_arns = merge(
    { "db-password" = aws_ssm_parameter.db_password.arn },
    { for k, v in data.aws_ssm_parameter.app_secrets : k => v.arn },
  )
}

# ---- 메인 스택: Kafka / EC2 관련 파라미터 ----

# Kafka EC2 사설 IP (3대 리스트): Terraform이 인스턴스를 만들면서 자동으로 채웁니다.
# 앱 서비스 (application.yml) 에서는 KAFKA_BOOTSTRAP_SERVERS 로 참조합니다.
resource "aws_ssm_parameter" "kafka_private_ip" {
  name  = "/${var.project}/${var.environment}/kafka/private-ip"
  type  = "String"
  value = join(",", [for i in aws_instance.kafka : "${i.private_ip}:9092"])
}

# Kafka Quorum 투표자 리스트 (3대): 브로커 간 클러스터 구성용 (예: 1@ip:9093,2@ip:9093,3@ip:9093)
resource "aws_ssm_parameter" "kafka_quorum_voters" {
  name  = "/${var.project}/${var.environment}/kafka/quorum-voters"
  type  = "String"
  value = join(",", [for i, inst in aws_instance.kafka : "${i + 1}@${inst.private_ip}:9093"])
}
