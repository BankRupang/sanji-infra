# ============================================================================
# 프로바이더 설정과 공통 조회(data) 리소스
# ============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ============================================================================
# 모듈 호출
# ============================================================================

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  primary_az         = var.primary_az
  admin_cidr         = var.admin_cidr
  acm_certificate_arn = var.acm_certificate_arn
}

module "edge" {
  source = "../../modules/edge"

  name                = local.name
  sg_alb_id           = module.network.sg_alb_id
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  acm_certificate_arn = var.acm_certificate_arn
}

module "iam" {
  source = "../../modules/iam"

  name               = local.name
  project            = var.project
  aws_region         = var.aws_region
  account_id         = data.aws_caller_identity.current.account_id
  enable_github_oidc = var.enable_github_oidc
  github_repo        = var.github_repo
}

module "compute_ec2" {
  source = "../../modules/compute-ec2"

  name                      = local.name
  kafka_count               = var.kafka_count
  kafka_instance_type       = var.kafka_instance_type
  kafka_volume_size         = var.kafka_volume_size
  monitoring_instance_type  = var.monitoring_instance_type
  monitoring_volume_size    = var.monitoring_volume_size
  primary_public_subnet_id  = module.network.primary_public_subnet_id
  sg_kafka_id               = module.network.sg_kafka_id
  sg_monitoring_id          = module.network.sg_monitoring_id
  ec2_key_name              = var.ec2_key_name
  iam_instance_profile_name = module.iam.ec2_instance_profile_name
  ami_id                    = data.aws_ami.al2023.id
}

module "data" {
  source = "../../modules/data"

  name                   = local.name
  project                = var.project
  environment            = var.environment
  aws_region             = var.aws_region
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  db_instance_class      = var.db_instance_class
  db_allocated_storage   = var.db_allocated_storage
  db_engine_version      = var.db_engine_version
  redis_node_type        = var.redis_node_type
  redis_engine_version   = var.redis_engine_version
  primary_az             = var.primary_az
  private_subnet_ids     = module.network.private_subnet_ids
  sg_rds_id              = module.network.sg_rds_id
  sg_redis_id            = module.network.sg_redis_id
  monitoring_instance_id = module.compute_ec2.monitoring_instance_id
  db_password_ssm_path   = "/${var.project}/${var.environment}/db/password"
  db_init_script_hash    = filemd5("${path.root}/../../scripts/db-schema-init.sh")
  bash_path              = var.bash_path
}

module "ecs" {
  source = "../../modules/ecs"

  name                        = local.name
  project                     = var.project
  aws_region                  = var.aws_region
  spring_profile              = var.spring_profile
  service_namespace           = var.service_namespace
  keycloak_realm              = var.keycloak_realm
  container_image_tag         = var.container_image_tag
  primary_public_subnet_id    = module.network.primary_public_subnet_id
  sg_ecs_id                   = module.network.sg_ecs_id
  vpc_id                      = module.network.vpc_id
  target_group_gateway_arn    = module.edge.target_group_gateway_arn
  rds_address                 = module.data.rds_address
  db_name                     = var.db_name
  db_username                 = var.db_username
  redis_address               = module.data.redis_address
  kafka_bootstrap_servers     = module.compute_ec2.kafka_bootstrap_servers
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  ecs_task_role_arn           = module.iam.ecs_task_role_arn
  secret_arns                 = module.ssm.secret_arns
  bid_min_capacity            = var.bid_min_capacity
  bid_max_capacity            = var.bid_max_capacity
  bid_cpu_target              = var.bid_cpu_target
  monitoring_private_ip       = module.compute_ec2.monitoring_private_ip
  fargate_on_demand_base      = var.fargate_on_demand_base
  fargate_on_demand_weight    = var.fargate_on_demand_weight
  fargate_spot_weight         = var.fargate_spot_weight
}

module "ssm" {
  source = "../../modules/ssm"

  project                 = var.project
  environment             = var.environment
  db_password             = var.db_password
  kafka_bootstrap_servers = module.compute_ec2.kafka_bootstrap_servers
  kafka_quorum_voters     = module.compute_ec2.kafka_quorum_voters
}

module "observability" {
  source = "../../modules/observability"

  name                     = local.name
  alert_email              = var.alert_email
  alb_arn_suffix           = module.edge.alb_arn_suffix
  rds_identifier           = module.data.rds_identifier
  redis_cluster_id         = module.data.redis_cluster_id
  ecs_cluster_name         = module.ecs.cluster_name
  bid_service_name         = module.ecs.bid_service_name
  kafka_instance_ids       = [for i in module.compute_ec2.kafka_instances : i.id]
  monitoring_instance_id   = module.compute_ec2.monitoring_instance_id
  kafka_instance_type      = var.kafka_instance_type
  monitoring_instance_type = var.monitoring_instance_type
  redis_node_type          = var.redis_node_type
  db_instance_class        = var.db_instance_class
}
