output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "bid_service_name" {
  value = aws_ecs_service.bid.name
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "discovery_namespace_id" {
  value = aws_service_discovery_private_dns_namespace.main.id
}
