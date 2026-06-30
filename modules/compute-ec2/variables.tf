variable "name" {
  type = string
}

variable "kafka_instance_type" {
  type = string
}

variable "kafka_volume_size" {
  type = number
}

variable "monitoring_instance_type" {
  type = string
}

variable "monitoring_volume_size" {
  type = number
}

variable "primary_public_subnet_id" {
  type = string
}

variable "sg_kafka_id" {
  type = string
}

variable "sg_monitoring_id" {
  type = string
}

variable "ec2_key_name" {
  description = "EC2 SSH 키페어 이름. 비워두면 SSM Session Manager로만 접속"
  type        = string
  default     = ""
}

variable "iam_instance_profile_name" {
  description = "EC2에 붙일 IAM 인스턴스 프로파일 이름"
  type        = string
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID"
  type        = string
}
