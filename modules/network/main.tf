# ============================================================================
# 네트워크: VPC, 서브넷, IGW, 라우팅 + 보안 그룹
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  for_each = var.availability_zones

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.public_cidr
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = var.availability_zones

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.private_cidr
  availability_zone = each.key

  tags = { Name = "${var.name}-private-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ============================================================================
# 보안 그룹
# ============================================================================

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB front door"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs-sg"
  description = "ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-rds-sg" }
}

resource "aws_security_group" "redis" {
  name        = "${var.name}-redis-sg"
  description = "ElastiCache Redis"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-redis-sg" }
}

resource "aws_security_group" "kafka" {
  name        = "${var.name}-kafka-sg"
  description = "Kafka EC2"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-kafka-sg" }
}

resource "aws_security_group" "monitoring" {
  name        = "${var.name}-monitoring-sg"
  description = "Monitoring EC2 (Prometheus/Loki/Grafana)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-monitoring-sg" }
}

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

resource "aws_security_group_rule" "ecs_in_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to gateway"
}

resource "aws_security_group_rule" "ecs_in_self" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.ecs.id
  description              = "service to service"
}

resource "aws_security_group_rule" "ecs_in_from_monitoring" {
  for_each = toset(["8000", "8761", "8888", "19091", "19092", "19093", "19094", "19095", "19096", "19097"])

  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = tonumber(each.value)
  to_port                  = tonumber(each.value)
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  description              = "Prometheus scrape ECS actuator ${each.value}"
}

resource "aws_security_group_rule" "rds_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS to PostgreSQL"
}

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

resource "aws_security_group_rule" "redis_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.redis.id
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS to Redis"
}

resource "aws_security_group_rule" "kafka_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.kafka.id
  from_port                = 9092
  to_port                  = 9092
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS to Kafka broker"
}

resource "aws_security_group_rule" "kafka_in_from_monitoring" {
  for_each = toset(["9092", "7071", "9100"])

  type                     = "ingress"
  security_group_id        = aws_security_group.kafka.id
  from_port                = tonumber(each.value)
  to_port                  = tonumber(each.value)
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  description              = "Monitoring scrape Kafka port ${each.value}"
}

resource "aws_security_group_rule" "kafka_in_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.kafka.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  description       = "admin SSH"
}

resource "aws_security_group_rule" "kafka_in_self" {
  type                     = "ingress"
  security_group_id        = aws_security_group.kafka.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.kafka.id
  description              = "Kafka internal communication (9092, 9093)"
}

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

resource "aws_security_group_rule" "monitoring_in_loki_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.monitoring.id
  from_port                = 3100
  to_port                  = 3100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  description              = "ECS logs to Loki"
}
