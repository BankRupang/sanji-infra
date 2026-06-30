variable "name" {
  type = string
}

variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "spring_profile" {
  type = string
}

variable "service_namespace" {
  description = "Cloud Map 사설 DNS 네임스페이스 (예: sanji.local)"
  type        = string
}

variable "keycloak_realm" {
  type = string
}

variable "container_image_tag" {
  description = "태스크 정의 최초 생성 시 쓸 이미지 태그. 이후 배포는 CI/CD가 SHA 태그로 교체"
  type        = string
  default     = "latest"
}

variable "primary_public_subnet_id" {
  type = string
}

variable "sg_ecs_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "target_group_gateway_arn" {
  description = "ALB gateway 대상 그룹 ARN"
  type        = string
}

variable "rds_address" {
  description = "RDS 호스트 주소"
  type        = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "redis_address" {
  description = "Redis 노드 주소"
  type        = string
}

variable "kafka_bootstrap_servers" {
  description = "Kafka 브로커 주소 목록 (쉼표 구분). 예: 10.0.1.10:9092,10.0.1.11:9092,10.0.1.12:9092"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  type = string
}

variable "ecs_task_role_arn" {
  type = string
}

variable "secret_arns" {
  description = "시크릿 키 -> SSM 파라미터 ARN 맵 (ssm.tf의 secret_arns와 동일 구조)"
  type        = map(string)
}

variable "bid_min_capacity" {
  type = number
}

variable "bid_max_capacity" {
  type = number
}

variable "bid_cpu_target" {
  type = number
}

variable "monitoring_private_ip" {
  description = "모니터링 EC2 사설 IP (Loki push URL 생성에 사용)"
  type        = string
}

