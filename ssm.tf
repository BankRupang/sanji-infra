# ============================================================================
# SSM Parameter Store: 시크릿 보관함
# ============================================================================
# 시크릿은 코드에 직접 쓰지 않고 SSM Parameter Store(SecureString)에 둡니다.
#
# 중요한 패턴 두 가지:
#   1) db_password 만 Terraform 변수로 직접 넣습니다. (RDS 생성에 필요하기 때문)
#   2) 나머지 시크릿은 "CHANGE_ME" 빈 칸으로만 만들어 둡니다.
#      실제 값은 AWS 콘솔이나 CLI로 따로 채웁니다.
#      lifecycle.ignore_changes 가 걸려 있어, 사람이 채운 값을
#      Terraform이 다시 "CHANGE_ME"로 덮어쓰지 않습니다.

# --- 앱이 쓰는 시크릿들의 경로표 ---
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

# DB 비밀번호: 변수 값으로 채웁니다. RDS와 같은 값을 앱도 SSM으로 읽습니다.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.environment}/db/password"
  type  = "SecureString"
  value = var.db_password
}

# 나머지 앱 시크릿: 빈 칸으로 생성. 실제 값은 배포 가이드대로 따로 입력.
resource "aws_ssm_parameter" "app_secrets" {
  for_each = local.app_secret_paths

  name  = each.value
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value] # 사람이 채운 실제 값을 보존
  }
}

# ECS 태스크 정의에서 "시크릿 키 -> 해당 SSM 파라미터 ARN"을 찾을 때 쓰는 표
locals {
  secret_arns = merge(
    { "db-password" = aws_ssm_parameter.db_password.arn },
    { for k, v in aws_ssm_parameter.app_secrets : k => v.arn },
  )
}

# ----------------------------------------------------------------------------
# EC2(Kafka, 모니터링)가 시작 스크립트에서 읽는 파라미터들
# 경로는 기존 docker-compose / 배포 가이드와 똑같이 맞춥니다.
# ----------------------------------------------------------------------------

# Kafka Cluster ID: 최초 1회 UUID를 만들어 넣어야 합니다. (배포 가이드 1단계)
resource "aws_ssm_parameter" "kafka_cluster_id" {
  name  = "/${var.project}/kafka/cluster-id"
  type  = "SecureString"
  value = "CHANGE_ME" # 배포 가이드의 kafka-storage.sh random-uuid 결과로 교체
  lifecycle {
    ignore_changes = [value]
  }
}

# Kafka EC2 사설 IP: Terraform이 인스턴스를 만들면서 자동으로 채웁니다.
# (기존 가이드는 수동 등록이었지만, IP를 Terraform이 알고 있으니 자동화합니다)
resource "aws_ssm_parameter" "kafka_private_ip" {
  name  = "/${var.project}/kafka/private-ip"
  type  = "String"
  value = aws_instance.kafka.private_ip
}

# Grafana 관리자 비밀번호
resource "aws_ssm_parameter" "grafana_admin_password" {
  name  = "/${var.project}/monitoring/grafana-admin-password"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle {
    ignore_changes = [value]
  }
}

# Grafana 알림용 Slack Webhook
resource "aws_ssm_parameter" "monitoring_slack_webhook" {
  name  = "/${var.project}/monitoring/slack-webhook-url"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle {
    ignore_changes = [value]
  }
}
