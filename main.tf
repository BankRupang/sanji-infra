# ============================================================================
# 프로바이더 설정과 공통 조회(data) 리소스
# ============================================================================
# Terraform이 어느 클라우드, 어느 리전에 리소스를 만들지 정합니다.

provider "aws" {
  region = var.aws_region

  # 여기 적은 태그가 Terraform이 만드는 "모든" 리소스에 자동으로 붙습니다.
  # 콘솔에서 "이건 Terraform이 만든 거구나"를 한눈에 알 수 있어 관리가 쉽습니다.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# --- 아래 data 블록은 "새 리소스를 만드는 게 아니라" 기존 정보를 조회만 합니다 ---

# 현재 사용 중인 AWS 계정 ID (IAM 정책에서 계정 번호가 필요할 때 사용)
data "aws_caller_identity" "current" {}

# 현재 리전 정보
data "aws_region" "current" {}

# EC2(Kafka, 모니터링)에 쓸 최신 Amazon Linux 2023 이미지(AMI)를 자동으로 찾습니다.
# AMI ID는 리전마다 다르고 자주 바뀌므로 직접 적지 않고 조회로 가져옵니다.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
