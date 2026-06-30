variable "name" {
  type = string
}

variable "sg_alb_id" {
  description = "ALB 보안 그룹 ID"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "ALB가 들어갈 퍼블릭 서브넷 ID 목록 (최소 2개 AZ)"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "HTTPS 리스너용 ACM 인증서 ARN. 비워두면 HTTP만 사용"
  type        = string
  default     = ""
}
