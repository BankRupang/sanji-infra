# ============================================================================
# 보안 그룹(Security Group)
# ============================================================================
# 보안 그룹은 자원 앞에 선 방화벽입니다.
# 인바운드(들어오는 트래픽)는 꼭 필요한 것만 허용합니다. 외부로 열린 문은 ALB 하나뿐입니다.
#
# 두 보안 그룹이 서로를 가리키면(예: ECS ↔ 모니터링) 순환 참조가 생기므로
# 규칙은 보안 그룹과 분리한 aws_security_group_rule 로 따로 답니다.

# 빈 보안 그룹 5개를 먼저 만들고 규칙은 아래에서 붙입니다.
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB front door"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs-sg"
  description = "ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-rds-sg" }
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis-sg"
  description = "ElastiCache Redis"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-redis-sg" }
}

resource "aws_security_group" "kafka" {
  name        = "${local.name}-kafka-sg"
  description = "Kafka EC2"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-kafka-sg" }
}

resource "aws_security_group" "monitoring" {
  name        = "${local.name}-monitoring-sg"
  description = "Monitoring EC2 (Prometheus/Loki/Grafana)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-monitoring-sg" }
}

# 모든 보안 그룹의 아웃바운드(나가는 트래픽)는 전부 허용합니다.
# (ECR pull, 외부 API 호출, AWS API 등 나가는 길은 막지 않습니다)
resource "aws_security_group_rule" "egress_all" {
  for_each = {
    alb        = aws_security_group.alb.id
    ecs        = aws_security_group.ecs.id
    rds        = aws_security_group.rds.id
    redis      = aws_security_group.redis.id
    kafka      = aws_security_group.kafka.id
    monitoring = aws_security_group.monitoring.id
  }
  type              = "egress"
  security_group_id = each.value
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "allow all outbound"
}

# --- ALB: 외부에서 오는 HTTP(80) 허용 (HTTPS는 인증서 있을 때) ---
resource "aws_security_group_rule" "alb_in_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "public HTTP"
}

resource "aws_security_group_rule" "alb_in_https" {
  count             = var.acm_certificate_arn != "" ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "public HTTPS"
}

# --- ECS 태스크 ---
# 1) ALB가 gateway(8000)로 보내는 트래픽 허용
resource "aws_security_group_rule" "ecs_in_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to gateway"
}

# 2) 서비스끼리 서로 호출(Eureka, Config, STOMP 등) 같은 SG 안끼리 전부 허용
resource "aws_security_group_rule" "ecs_in_self" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.ecs.id
  description              = "service to service"
}

# 3) 모니터링 EC2의 Prometheus가 각 태스크의 /actuator/prometheus 를 긁어감
resource "aws_security_group_rule" "ecs_in_from_monitoring" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  description              = "Prometheus scrape actuator"
}

# --- RDS: ECS 태스크에서 오는 5432만 허용 ---
resource "aws_security_group_rule" "rds_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS to PostgreSQL"
}

# 모니터링 EC2에서 DB 스키마 초기화 등 관리 작업용
# RDS가 Private Subnet에 있어 SQL 파일을 실행하려면 VPC 안에 있는 무언가가 대신 실행해줘야 함
# db_init만을 위해 별도 EC2(Bastion)를 만드는 것은 실익이 없다고 판단했음
resource "aws_security_group_rule" "rds_in_from_monitoring" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  description              = "Monitoring EC2 admin access to PostgreSQL"
}

# --- Redis: ECS 태스크에서 오는 6379만 허용 ---
resource "aws_security_group_rule" "redis_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.redis.id
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS to Redis"
}

# --- Kafka EC2 ---
# 1) ECS 태스크(프로듀서/컨슈머)에서 9092 허용
resource "aws_security_group_rule" "kafka_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.kafka.id
  from_port                = 9092
  to_port                  = 9092
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS to Kafka broker"
}

# 2) 모니터링 EC2가 JMX Exporter(7071), Node Exporter(9100), Kafka(9092 for UI) 를 봄
resource "aws_security_group_rule" "kafka_in_from_monitoring" {
  type                     = "ingress"
  security_group_id        = aws_security_group.kafka.id
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  description              = "Monitoring scrape + Kafka UI"
}

# 3) 관리자 SSH(22) (키페어가 있을 때만 의미 있음)
resource "aws_security_group_rule" "kafka_in_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.kafka.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  description       = "admin SSH"
}

# --- 모니터링 EC2 ---
# 1) 관리자 브라우저 접근: Grafana(3000), Prometheus(9090), Kafka UI(8080), SSH(22)
resource "aws_security_group_rule" "monitoring_in_admin" {
  for_each          = toset(["3000", "9090", "8080", "22"])
  type              = "ingress"
  security_group_id = aws_security_group.monitoring.id
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  description       = "admin access ${each.value}"
}

# 2) ECS 앱이 로그를 Loki(3100)로 push
resource "aws_security_group_rule" "monitoring_in_loki_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.monitoring.id
  from_port                = 3100
  to_port                  = 3100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS logs to Loki"
}
