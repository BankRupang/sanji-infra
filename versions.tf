# ============================================================================
# Terraform 본체와 프로바이더 버전 고정
# ============================================================================
# 이 파일은 "어떤 버전의 Terraform과 AWS 플러그인을 쓸지"를 적어둡니다.
# 버전을 고정해두면 팀원이 각자 다른 버전을 써서 결과가 달라지는 일을 막습니다.

terraform {
  # Terraform 실행 파일 자체의 최소 버전
  required_version = ">= 1.10.0"

  # 사용할 프로바이더(클라우드 플러그인) 목록
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40" # 5.40 이상 6.0 미만
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # --------------------------------------------------------------------------
  # 상태 파일(state) 저장 위치
  # --------------------------------------------------------------------------
  # 상태 파일을 S3에 저장하고 DynamoDB로 동시 apply를 막습니다.
  # (주의: 이 폴더를 apply하기 전에 bootstrap 폴더를 먼저 apply해야 합니다.)
  #   cd bootstrap && terraform init && terraform apply && cd ..
  # 잠금은 DynamoDB 없이 S3 잠금 파일(use_lockfile)로 처리합니다. (Terraform >= 1.10)
  backend "s3" {
    bucket         = "sanji-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}