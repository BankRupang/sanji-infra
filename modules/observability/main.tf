# ============================================================================
# CloudWatch 경보: ALB 5xx, RDS/Redis/Bid CPU 임계값 초과 시 SNS 이메일 알림
# ============================================================================

resource "aws_sns_topic" "alerts" {
  count = var.alert_email != "" ? 1 : 0
  name  = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.001
  alarm_description   = "ALB 5xx 에러율 0.1% 초과"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "m1/m2"
    label       = "5xx Error Rate"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "RDS CPU 사용률 70% 초과"
  dimensions          = { DBInstanceIdentifier = var.rds_identifier }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.name}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Redis CPU 사용률 70% 초과 (t3.micro 크레딧 주의)"
  dimensions          = { CacheClusterId = var.redis_cluster_id }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "bid_cpu" {
  alarm_name          = "${var.name}-bid-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Bid 서비스 CPU 70% 초과 (스케일아웃 한계 점검)"
  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.bid_service_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# ----------------------------------------------------------------------------
# t3 CPU 크레딧 잔량 경보
# ----------------------------------------------------------------------------

locals {
  t3_max_credits = {
    nano      = 144
    micro     = 288
    small     = 576
    medium    = 576
    large     = 864
    xlarge    = 2304
    "2xlarge" = 4608
  }

  # Kafka 3대 각각 + 모니터링 + Redis + RDS
  kafka_alarm_targets = {
    for idx in range(length(var.kafka_instance_ids)) : "kafka-${idx + 1}" => {
      type       = var.kafka_instance_type
      namespace  = "AWS/EC2"
      dimensions = { InstanceId = var.kafka_instance_ids[idx] }
    }
  }

  non_kafka_alarm_targets = {
    monitoring = {
      type       = var.monitoring_instance_type
      namespace  = "AWS/EC2"
      dimensions = { InstanceId = var.monitoring_instance_id }
    }
    redis = {
      type       = var.redis_node_type
      namespace  = "AWS/ElastiCache"
      dimensions = { CacheClusterId = var.redis_cluster_id }
    }
    rds = {
      type       = var.db_instance_class
      namespace  = "AWS/RDS"
      dimensions = { DBInstanceIdentifier = var.rds_identifier }
    }
  }

  all_credit_targets = merge(local.kafka_alarm_targets, local.non_kafka_alarm_targets)

  credit_alarms = {
    for k, v in local.all_credit_targets : k => merge(v, {
      threshold = lookup(local.t3_max_credits, reverse(split(".", v.type))[0], 576) * 0.2
    })
    if startswith(reverse(split(".", v.type))[1], "t")
  }
}

resource "aws_cloudwatch_metric_alarm" "credit_balance_low" {
  for_each = local.credit_alarms

  alarm_name          = "${var.name}-${each.key}-credit-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUCreditBalance"
  namespace           = each.value.namespace
  period              = 300
  statistic           = "Average"
  threshold           = each.value.threshold
  alarm_description   = "${each.key} t3 CPU 크레딧 잔량이 20%(약 ${each.value.threshold}개) 미만. 소진 시 성능 급락 위험."
  dimensions          = each.value.dimensions
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  treat_missing_data  = "notBreaching"
}
