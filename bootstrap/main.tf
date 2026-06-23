# ============================================================================
# Bootstrap: Terraform 상태 저장용 S3 버킷 + DynamoDB 테이블
# ============================================================================
# 본 인프라(.terraform/*.tf)를 처음 apply하기 전에 여기서 먼저 실행합니다.
#
# 사용 방법:
#   cd .terraform/bootstrap
#   terraform init
#   terraform apply
#
# 이후 상위 폴더로 돌아가서 본 인프라를 apply합니다.
#   cd ..
#   terraform init    <- "로컬 상태를 S3로 옮길까요?" 라고 물으면 yes
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
# DynamoDB 테이블: 동시 apply 잠금
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "tf_lock" {
  name         = "sanji-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ----------------------------------------------------------------------------
# 출력: apply 후 확인용
# ----------------------------------------------------------------------------
output "s3_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}
