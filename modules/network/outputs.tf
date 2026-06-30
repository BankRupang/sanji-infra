output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  description = "AZ별 퍼블릭 서브넷 맵"
  value       = aws_subnet.public
}

output "private_subnets" {
  description = "AZ별 프라이빗 서브넷 맵"
  value       = aws_subnet.private
}

output "primary_public_subnet_id" {
  value = aws_subnet.public[var.primary_az].id
}

output "primary_private_subnet_id" {
  value = aws_subnet.private[var.primary_az].id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "sg_alb_id" {
  value = aws_security_group.alb.id
}

output "sg_ecs_id" {
  value = aws_security_group.ecs.id
}

output "sg_rds_id" {
  value = aws_security_group.rds.id
}

output "sg_redis_id" {
  value = aws_security_group.redis.id
}

output "sg_kafka_id" {
  value = aws_security_group.kafka.id
}

output "sg_monitoring_id" {
  value = aws_security_group.monitoring.id
}
