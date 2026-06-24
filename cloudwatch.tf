# ============================================================================
# CloudWatch 경보: ALB 5xx, RDS/Redis/Bid CPU 임계값 초과 시 SNS 이메일 알림
# ============================================================================
# 비즈니스 지표 알람은 Grafana/Prometheus에서 다루고,
# 여기서는 AWS 관리형 자원(ALB, RDS, Redis, ECS)의 기본 경보만 둡니다.

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
  # 경보 발생 시 알릴 대상. 이메일이 없으면 빈 목록(알림 없이 콘솔에만 표시)
  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
}

# ALB 5xx 에러율 (SLO: 5xx 0.1% 이하)
# metric_query로 "5xx건수 / 전체요청수"를 직접 계산합니다.
# 트래픽이 없을 때는 분모가 0이 되어 결과가 null -> notBreaching(정상)으로 처리합니다.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.001 # 0.1%
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
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }
}

# RDS CPU (CPU 70% 이상 5분 지속)
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

# 입찰(bid) 서비스 CPU (오토스케일 목표 60%, 경보는 보수적으로 70%)
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

# ----------------------------------------------------------------------------
# t3 CPU 크레딧 잔량 경보 (t3 리스크 / 알람 임계값 표: 20% 이하)
# ----------------------------------------------------------------------------
# t3 같은 버스터블 인스턴스는 평소 쌓아둔 CPU 크레딧을 피크에 몰아 씁니다.
# 크레딧이 0이 되면 성능이 baseline으로 급락하므로, 20% 남았을 때 미리 알립니다.
# (20%면 m5/c5로 교체하거나 대응할 시간을 법니다)
#
# CPUCreditBalance 지표는 남은 크레딧 개수라서 임계값이 인스턴스 크기마다 다릅니다.
# 그래서 크기별 24시간 최대 누적 크레딧 표를 두고, 그 20%를 임계값으로 계산합니다.
# 인스턴스 타입을 m5/c5 같은 고정형으로 바꾸면(크레딧 개념이 없어 지표도 없음)
# 아래 for_each 조건에서 자동으로 빠져 경보가 생성되지 않습니다.

locals {
  # t3/t3a/t4g 크기별 24시간 최대 누적 크레딧 (= 시간당 적립량 x 24)
  t3_max_credits = {
    nano      = 144
    micro     = 288
    small     = 576
    medium    = 576
    large     = 864
    xlarge    = 2304
    "2xlarge" = 4608
  }

  # 크레딧 경보를 걸 후보 자원들 (EC2 2대 + Redis + RDS)
  credit_alarm_targets = {
    kafka = {
      type       = var.kafka_instance_type
      namespace  = "AWS/EC2"
      dimensions = { InstanceId = aws_instance.kafka.id }
    }
    monitoring = {
      type       = var.monitoring_instance_type
      namespace  = "AWS/EC2"
      dimensions = { InstanceId = aws_instance.monitoring.id }
    }
    redis = {
      type       = var.redis_node_type
      namespace  = "AWS/ElastiCache"
      dimensions = { CacheClusterId = aws_elasticache_cluster.redis.cluster_id }
    }
    rds = {
      type       = var.db_instance_class
      namespace  = "AWS/RDS"
      dimensions = { DBInstanceIdentifier = aws_db_instance.main.identifier }
    }
  }

  # 타입 문자열에서 계열(family)과 크기(size)를 뽑습니다.
  #   "t3.medium" → family "t3", size "medium"
  #   "cache.t3.micro" / "db.t3.micro" → family "t3", size "micro"
  # 계열이 t로 시작하는(버스터블) 자원만 남기고 최대 크레딧의 20%를 임계값으로 둡니다.
  credit_alarms = {
    for k, v in local.credit_alarm_targets : k => merge(v, {
      threshold = lookup(local.t3_max_credits, reverse(split(".", v.type))[0], 576) * 0.2
    })
    if startswith(reverse(split(".", v.type))[1], "t")
  }
}

resource "aws_cloudwatch_metric_alarm" "credit_balance_low" {
  for_each = local.credit_alarms

  alarm_name          = "${local.name}-${each.key}-credit-low"
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
  # 고정형 인스턴스로 바꾸면 지표가 사라지는데 그때 "데이터 없음"을 정상으로 처리
  treat_missing_data = "notBreaching"
}
