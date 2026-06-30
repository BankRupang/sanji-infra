variable "project" {
  description = "프로젝트 이름 (예: sanji)"
  type        = string
}

variable "environment" {
  description = "배포 환경 (prod 또는 dev)"
  type        = string
}

variable "db_password" {
  description = "RDS 데이터베이스 비밀번호"
  type        = string
  sensitive   = true
}

variable "kafka_bootstrap_servers" {
  description = "Kafka 브로커 연결 주소 (쉼표 구분)"
  type        = string
}

variable "kafka_quorum_voters" {
  description = "Kafka KRaft 투표자 목록"
  type        = string
}
