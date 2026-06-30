variable "name" {
  description = "리소스 이름 접두사 (예: sanji-prod)"
  type        = string
}

variable "project" {
  description = "프로젝트 이름 (예: sanji)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "account_id" {
  description = "AWS 계정 ID"
  type        = string
}

variable "enable_github_oidc" {
  description = "GitHub Actions OIDC 역할 생성 여부. dev는 false로 설정."
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub 저장소 (owner/repo 형식). enable_github_oidc = true 일 때 필수."
  type        = string
  default     = ""
}
