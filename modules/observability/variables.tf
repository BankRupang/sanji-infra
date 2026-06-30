variable "name" {
  type = string
}

variable "alert_email" {
  description = "CloudWatch 경보를 받을 이메일. 비워두면 SNS 구독을 만들지 않음"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN 축약 (CloudWatch dimensions 용)"
  type        = string
}

variable "rds_identifier" {
  type = string
}

variable "redis_cluster_id" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "bid_service_name" {
  type = string
}

variable "kafka_instance_ids" {
  description = "Kafka EC2 인스턴스 ID 목록 (3대)"
  type        = list(string)
}

variable "monitoring_instance_id" {
  type = string
}

variable "kafka_instance_type" {
  type = string
}

variable "monitoring_instance_type" {
  type = string
}

variable "redis_node_type" {
  type = string
}

variable "db_instance_class" {
  type = string
}
