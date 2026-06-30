output "kafka_instances" {
  description = "Kafka EC2 인스턴스 목록"
  value       = aws_instance.kafka
}

output "kafka_private_ips" {
  value = [for i in aws_instance.kafka : i.private_ip]
}

output "kafka_public_ips" {
  value = [for i in aws_instance.kafka : i.public_ip]
}

output "kafka_bootstrap_servers" {
  description = "Kafka 브로커 3대 주소 (쉼표 구분, 포트 포함)"
  value       = join(",", [for i in aws_instance.kafka : "${i.private_ip}:9092"])
}

output "kafka_quorum_voters" {
  description = "KRaft quorum voters 문자열 (예: 1@ip:9093,2@ip:9093,3@ip:9093)"
  value       = join(",", [for idx, inst in aws_instance.kafka : "${idx + 1}@${inst.private_ip}:9093"])
}

output "monitoring_instance_id" {
  value = aws_instance.monitoring.id
}

output "monitoring_private_ip" {
  value = aws_instance.monitoring.private_ip
}

output "monitoring_public_ip" {
  value = aws_instance.monitoring.public_ip
}
