# ============================================================================
# Bootstrap: Terraform 상태 저장용 S3 버킷
# ============================================================================
# 본 인프라(.terraform/*.tf)를 처음 apply하기 전에 여기서 먼저 실행합니다.
# S3 버킷 하나만 만들면 됩니다. 잠금은 use_lockfile 옵션으로 S3가 직접 처리합니다.
# (Terraform 1.10부터 DynamoDB 없이 S3 잠금 파일 방식으로 동작합니다.)
#
# 사용 방법:
#   cd .terraform/bootstrap
#   terraform init
#   terraform apply
#
# 이후 상위 폴더로 돌아가서 본 인프라를 apply합니다.
#   cd ..
#   terraform init
#   terraform apply
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
  # 이 폴더는 S3 backend 없이 로컬에 상태를 저장합니다.
  # bootstrap 리소스 자체를 Terraform이 관리할 필요가 없으므로 의도된 설계입니다.
}

provider "aws" {
  region = "ap-northeast-2"
}

# ----------------------------------------------------------------------------
# S3 버킷: 상태 파일 보관
# ----------------------------------------------------------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket = "sanji-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

# 버전 관리: 상태 파일이 실수로 덮어씌워져도 이전 버전으로 복구 가능
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 버킷 암호화: 상태 파일 안의 시크릿 값 보호
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 퍼블릭 접근 차단: 상태 파일이 외부에 노출되지 않도록
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------------------------------
# SSM Parameter Store: 메인 스택을 destroy해도 살아남아야 하는 시크릿
# ----------------------------------------------------------------------------
# 이 파라미터들은 메인 인프라(ECS, RDS 등)와 수명이 다릅니다.
# 인프라를 껐다 켜도 값을 다시 입력할 필요가 없도록 bootstrap에 둡니다.
# apply 후 ssm-restore.sh 를 최초 1회 실행해서 실제 값을 채웁니다.

locals {
  bootstrap_secrets = {
    "keycloak/client-secret"         = "/sanji/prod/keycloak/client-secret"
    "keycloak/admin-password"        = "/sanji/prod/keycloak/admin-password"
    "user/manager-key"               = "/sanji/prod/user/manager-key"
    "user/master-key"                = "/sanji/prod/user/master-key"
    "toss/client-key"                = "/sanji/prod/toss/client-key"
    "toss/secret-key"                = "/sanji/prod/toss/secret-key"
    "slack/webhook-url"              = "/sanji/prod/slack/webhook-url"
    "slack/bot-token"                = "/sanji/prod/slack/bot-token"
    "ai/gemini-api-key"              = "/sanji/prod/ai/gemini-api-key"
    "kafka/cluster-id"               = "/sanji/prod/kafka/cluster-id"
    "monitoring/grafana-admin-password" = "/sanji/prod/monitoring/grafana-admin-password"
    "monitoring/slack-webhook-url"   = "/sanji/prod/monitoring/slack-webhook-url"
    "langfuse/nextauth-secret"       = "/sanji/prod/langfuse/nextauth-secret"
    "langfuse/salt"                  = "/sanji/prod/langfuse/salt"
  }
}

resource "aws_ssm_parameter" "secrets" {
  for_each = local.bootstrap_secrets

  name  = each.value
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [value]
  }
}

# ----------------------------------------------------------------------------
# 출력: apply 후 확인용
# ----------------------------------------------------------------------------
output "s3_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "ssm_parameter_names" {
  value       = [for p in aws_ssm_parameter.secrets : p.name]
  description = "생성된 SSM 파라미터 목록"
}
