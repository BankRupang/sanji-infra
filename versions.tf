# ============================================================================
# Terraform 본체와 프로바이더 버전 고정
# ============================================================================
# 이 파일은 "어떤 버전의 Terraform과 AWS 플러그인을 쓸지"를 적어둡니다.
# 버전을 고정해두면 팀원이 각자 다른 버전을 써서 결과가 달라지는 일을 막습니다.

terraform {
  # Terraform 실행 파일 자체의 최소 버전
  required_version = ">= 1.5.0"

  # 사용할 프로바이더(클라우드 플러그인) 목록
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40" # 5.40 이상 6.0 미만
    }
  }

  # --------------------------------------------------------------------------
  # 상태 파일(state) 저장 위치
  # --------------------------------------------------------------------------
  # 상태 파일을 S3에 저장하고 DynamoDB로 동시 apply를 막습니다.
  # (주의: apply 전에 S3 버킷과 DynamoDB 테이블을 Terraform 밖에서 먼저 만들어야 합니다.)
  #   aws s3api create-bucket --bucket sanji-terraform-state --region ap-northeast-2 \
  #     --create-bucket-configuration LocationConstraint=ap-northeast-2
  #   aws s3api put-bucket-versioning --bucket sanji-terraform-state \
  #     --versioning-configuration Status=Enabled
  #   aws dynamodb create-table --table-name sanji-terraform-lock \
  #     --attribute-definitions AttributeName=LockID,AttributeType=S \
  #     --key-schema AttributeName=LockID,KeyType=HASH \
  #     --billing-mode PAY_PER_REQUEST --region ap-northeast-2
  backend "s3" {
    bucket         = "sanji-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "sanji-terraform-lock"
    encrypt        = true
  }
}