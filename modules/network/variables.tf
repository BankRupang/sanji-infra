variable "name" {
  description = "리소스 이름 접두사 (project-environment)"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = map(object({
    public_cidr  = string
    private_cidr = string
  }))
}

variable "primary_az" {
  description = "ECS/EC2가 실제로 뜨는 단일 AZ"
  type        = string
}

variable "admin_cidr" {
  description = "Grafana/Prometheus/Kafka UI/SSH에 접근을 허용할 관리자 IP 대역"
  type        = string
}

variable "acm_certificate_arn" {
  description = "HTTPS용 ACM 인증서 ARN. 비워두면 HTTPS SG 규칙을 만들지 않음"
  type        = string
  default     = ""
}
