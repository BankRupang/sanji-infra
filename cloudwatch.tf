# ============================================================================
# CloudWatch 경보: ALB 5xx, RDS/Redis/Bid CPU 임계값 초과 시 SNS 이메일 알림
# ============================================================================
# 깊은 비즈니스 지표 알람은 Grafana/Prometheus에서 다루고,
# 여기서는 AWS 관리형 자원(ALB, RDS, Redis, ECS)의 기본 경보만 둡니다.
# alert_email 변수를 채우면 이메일로 알림이 옵니다.

# 경보를 보낼 SNS 주제 (이메일이 있을 때만 생성)
resource "aws_sns_topic" "alerts" {
  count = var.alert_email != "" ? 1 : 0
  name  = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  # 경보 발생 시 알릴 대상. 이메일이 없으면 빈 목록(알림 없이 콘솔에만 표시).
  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
}

# ALB 5xx 에러 (문서 SLO: 5xx 0.1% 이하)
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5xx 에러 급증"
  dimensions          = { LoadBalancer = aws_lb.main.arn_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# RDS CPU (문서 알람: CPU 70% 이상 5분 지속)
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "RDS CPU 사용률 70% 초과"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Redis CPU
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${local.name}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Redis CPU 사용률 70% 초과 (t3.micro 크레딧 주의)"
  dimensions          = { CacheClusterId = aws_elasticache_cluster.redis.cluster_id }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# 입찰(bid) 서비스 CPU (문서: 오토스케일 목표 60%, 경보는 보수적으로 70%)
resource "aws_cloudwatch_metric_alarm" "bid_cpu" {
  alarm_name          = "${local.name}-bid-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Bid 서비스 CPU 70% 초과 (스케일아웃 한계 점검)"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.bid.name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}
