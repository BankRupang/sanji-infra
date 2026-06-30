# ============================================================================
# 입력 변수(variables) 모음
# ============================================================================

# --- 공통 ---

variable "project" {
  description = "프로젝트 이름. 모든 리소스 이름 앞에 붙습니다."
  type        = string
  default     = "sanji"
}

variable "environment" {
  description = "배포 환경 이름 (prod, dev 등)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "리소스를 만들 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "spring_profile" {
  description = "Spring 부팅 시 활성화할 프로파일"
  type        = string
  default     = "prod"
}

# --- 네트워크 ---

variable "vpc_cidr" {
  description = "VPC 전체 IP 대역"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = <<-EOT
    AZ별 퍼블릭/프라이빗 서브넷 IP 대역입니다.
    문서는 단일 AZ 운영이지만, ALB와 RDS는 규칙상 최소 2개 AZ가 필요해 2개를 정의합니다.
    실제 ECS 태스크와 EC2는 primary_az 한 곳에만 띄웁니다.
  EOT
  type = map(object({
    public_cidr  = string
    private_cidr = string
  }))
  default = {
    "ap-northeast-2a" = { public_cidr = "10.0.1.0/24", private_cidr = "10.0.11.0/24" }
    "ap-northeast-2c" = { public_cidr = "10.0.2.0/24", private_cidr = "10.0.12.0/24" }
  }
}

variable "primary_az" {
  description = "ECS 태스크와 EC2가 실제로 뜨는 단일 AZ. availability_zones의 키 중 하나여야 합니다."
  type        = string
  default     = "ap-northeast-2a"
}

variable "admin_cidr" {
  description = <<-EOT
    Grafana/Prometheus/Kafka UI/SSH에 접근을 허용할 관리자 IP 대역입니다.
    예: 사무실 공인 IP "1.2.3.4/32".
    기본값 0.0.0.0/0(전체 허용)은 위험하니 운영 전에 반드시 좁히세요.
  EOT
  type        = string
  default     = "0.0.0.0/0"
}

# --- 데이터베이스(RDS) ---

variable "db_name" {
  description = "RDS에 만들 기본 데이터베이스 이름 (서비스별 스키마로 나눠 씀)"
  type        = string
  default     = "sanji"
}

variable "db_username" {
  description = "RDS 마스터 계정 이름"
  type        = string
  default     = "sanji"
}

variable "db_password" {
  description = "RDS 마스터 비밀번호. ECS 앱도 SSM을 통해 같은 값을 읽습니다. (필수 입력)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS 인스턴스 사양"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS 디스크 크기(GB)"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL 버전 (pgvector 확장 지원 버전)"
  type        = string
  default     = "16.9"
}

# --- 캐시(ElastiCache Redis) ---

variable "redis_node_type" {
  description = "Redis 노드 사양. 문서는 t3.micro 시작, 부하 시 t3.medium 상향 검토."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Redis 버전"
  type        = string
  default     = "7.1"
}

# --- EC2 (Kafka, 모니터링) ---

variable "kafka_count" {
  description = "Kafka EC2 브로커 대수. dev=1, prod=3"
  type        = number
  default     = 3
}

variable "kafka_instance_type" {
  description = "Kafka EC2 사양"
  type        = string
  default     = "t3.medium"
}

variable "kafka_volume_size" {
  description = "Kafka EC2 디스크 크기(GB)"
  type        = number
  default     = 30
}

variable "monitoring_instance_type" {
  description = "모니터링(PLG) EC2 사양"
  type        = string
  default     = "t3.medium"
}

variable "monitoring_volume_size" {
  description = "모니터링 EC2 디스크 크기(GB)"
  type        = number
  default     = 50
}

variable "ec2_key_name" {
  description = "EC2에 SSH로 붙을 때 쓸 키페어 이름. 비워두면 SSH 없이 SSM Session Manager로만 접속합니다."
  type        = string
  default     = ""
}

# --- ECS / 컨테이너 ---

variable "container_image_tag" {
  description = "Terraform이 태스크 정의를 처음 만들 때 쓰는 이미지 태그. 배포 후에는 CI/CD가 SHA 태그 리비전으로 교체하므로 이 값이 직접 운영에 쓰이지는 않습니다."
  type        = string
  default     = "latest"
}

variable "service_namespace" {
  description = "서비스 디스커버리(Cloud Map) 내부 도메인. 예: config-server.sanji.local"
  type        = string
  default     = "sanji.local"
}

variable "keycloak_realm" {
  description = "Keycloak 렐름 이름"
  type        = string
  default     = "sanjijk"
}

# --- Bid 오토스케일링 ---

variable "bid_min_capacity" {
  description = "Bid 최소 태스크 수"
  type        = number
  default     = 2
}

variable "bid_max_capacity" {
  description = "Bid 최대 태스크 수"
  type        = number
  default     = 6
}

variable "bid_cpu_target" {
  description = "Bid scale-out 목표 CPU 평균(%). 60% 초과 시 태스크 추가."
  type        = number
  default     = 60
}

# --- ALB HTTPS (선택) ---

variable "acm_certificate_arn" {
  description = <<-EOT
    HTTPS(443)를 켜려면 ACM 인증서 ARN을 넣으세요.
    비워두면 HTTP(80)만 동작합니다. (문서: ALB 기본 DNS로 시작)
  EOT
  type        = string
  default     = ""
}

# --- GitHub Actions OIDC (CI/CD) ---

variable "enable_github_oidc" {
  description = "GitHub Actions가 키 없이 AWS에 배포하도록 OIDC 역할을 만들지 여부"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "OIDC 신뢰를 허용할 GitHub 저장소 (형식: 조직/저장소)"
  type        = string
  default     = "BankRupang/san-ji-jik-kyeng"
}

# --- 알람 ---

variable "alert_email" {
  description = "CloudWatch 경보를 받을 이메일. 비워두면 SNS 구독을 만들지 않습니다."
  type        = string
  default     = ""
}
