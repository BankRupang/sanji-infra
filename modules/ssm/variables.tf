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

variable "kafka_private_ips" {
  description = "Kafka 브로커 사설 IP 목록 (쉼표 구분, 포트 없음). 모니터링 스크립트가 prometheus 타겟으로 사용."
  type        = string
}

variable "kafka_quorum_voters" {
  description = "Kafka KRaft 투표자 목록"
  type        = string
}
