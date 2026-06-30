# ============================================================================
# RDS: PostgreSQL (단일 인스턴스 + 스키마 분리)
# ============================================================================
# 단일 RDS로 시작. AZ 장애 시 다운(SPOF)은 비용 절감을 위해 의도적으로 감수합니다.
# pgvector는 PostgreSQL 확장이라 별도 벡터 DB 없이 같은 RDS에서 처리합니다.

# DB 서브넷 그룹: RDS는 규칙상 최소 2개 AZ의 서브넷을 요구합니다.
# 그래서 프라이빗 서브넷 2개를 묶지만, 인스턴스는 primary_az 한 곳에만 둡니다.
resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnet"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = { Name = "${local.name}-db-subnet" }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # 네트워크: 프라이빗 서브넷, 외부 접근 차단, 단일 AZ
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zone      = var.primary_az
  multi_az               = false
  publicly_accessible    = false

  # CloudWatch가 지표를 받도록 함 (Grafana CloudWatch 데이터소스용)
  backup_retention_period = 7
  skip_final_snapshot     = true  # 연습/학습 편의. 운영에서는 false 권장
  deletion_protection     = false # 운영에서는 true 권장
  apply_immediately       = true

  tags = { Name = "${local.name}-postgres" }
}

# ============================================================================
# DB 스키마 초기화: Keycloak / Langfuse용 스키마 자동 생성
# ============================================================================
# Spring 서비스 스키마는 각 서비스의 Flyway(create-schemas: true)가 처리합니다.
# Flyway 관리 밖인 Keycloak, Langfuse 스키마만 여기서 생성합니다.
#
# RDS는 private subnet에 있어 직접 접근이 불가하므로,
# 모니터링 EC2를 경유하는 SSM Run Command를 사용합니다.
resource "null_resource" "db_schema_init" {
  depends_on = [
    aws_db_instance.main,
    aws_instance.monitoring,
    aws_ssm_parameter.db_password,
  ]

  # RDS 인스턴스가 처음 만들어질 때만 실행 (재생성 시에도 재실행)
  triggers = {
    rds_id = aws_db_instance.main.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      REGION      = var.aws_region
      INSTANCE_ID = aws_instance.monitoring.id
      RDS_HOST    = aws_db_instance.main.address
      DB_USER     = var.db_username
      DB_NAME     = var.db_name
      SSM_PW_PATH = "/${var.project}/${var.environment}/db/password"
    }
    command = "bash ${path.module}/scripts/db-schema-init.sh"
  }
}
