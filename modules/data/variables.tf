variable "name" {
  type = string
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage" {
  type = number
}

variable "db_engine_version" {
  type = string
}

variable "redis_node_type" {
  type = string
}

variable "redis_engine_version" {
  type = string
}

variable "primary_az" {
  type = string
}

variable "private_subnet_ids" {
  description = "RDS/Redis가 들어갈 프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "sg_rds_id" {
  type = string
}

variable "sg_redis_id" {
  type = string
}

variable "monitoring_instance_id" {
  description = "db-schema-init SSM Run Command를 실행할 모니터링 EC2 인스턴스 ID"
  type        = string
}

variable "db_password_ssm_path" {
  description = "DB 비밀번호가 저장된 SSM 파라미터 경로. 스크립트가 이 경로로 비밀번호를 읽음"
  type        = string
}
