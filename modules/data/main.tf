# ============================================================================
# RDS: PostgreSQL + ElastiCache: Redis
# ============================================================================

resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db-subnet"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name}-db-subnet" }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_rds_id]
  availability_zone      = var.primary_az
  multi_az               = false
  publicly_accessible    = false

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = { Name = "${var.name}-postgres" }
}

# DB 스키마 초기화: Keycloak / Langfuse용 스키마 자동 생성
# Spring 서비스 스키마는 각 서비스의 Flyway가 처리합니다.
# Flyway 관리 밖인 Keycloak, Langfuse 스키마만 여기서 생성합니다.
resource "null_resource" "db_schema_init" {
  depends_on = [aws_db_instance.main]

  triggers = {
    rds_id      = aws_db_instance.main.id
    script_hash = filemd5("${path.root}/scripts/db-schema-init.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      REGION      = var.aws_region
      INSTANCE_ID = var.monitoring_instance_id
      RDS_HOST    = aws_db_instance.main.address
      DB_USER     = var.db_username
      DB_NAME     = var.db_name
      SSM_PW_PATH = var.db_password_ssm_path
    }
    command = "bash ${path.root}/scripts/db-schema-init.sh"
  }
}

# ============================================================================
# ElastiCache: Redis
# ============================================================================

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name}-redis-subnet"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.name}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.sg_redis_id]

  availability_zone = var.primary_az

  tags = { Name = "${var.name}-redis" }
}
