# ============================================================================
# EC2: Kafka 브로커, 모니터링(PLG) 서버
# ============================================================================
# stateful(데이터가 디스크에 남아야 하는) Kafka와 모니터링은
# 컨테이너가 통째로 교체되는 Fargate 대신, 디스크가 유지되는 EC2 + Docker Compose로 운영.
#
# 실제 배포(git clone, compose up)는 SSM Run Command로 합니다. (배포 가이드 참고)
# 여기 user_data는 도커/도커컴포즈/git/awscli 같은 "도구 설치"까지만 합니다.

locals {
  # EC2 부팅 시 1회 실행되는 설치 스크립트 (Kafka, 모니터링 공통)
  ec2_bootstrap = <<-EOT
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker git gettext
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # Docker Compose v2 플러그인 설치
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # 이후 단계(레포 clone, compose pull && up)는 SSM Run Command로 실행합니다.
    # (Amazon Linux 2023은 SSM Agent와 AWS CLI v2가 기본 설치되어 있습니다)
  EOT
}

# --- Kafka EC2 ---
resource "aws_instance" "kafka" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.kafka_instance_type
  subnet_id                   = local.primary_public_subnet_id
  vpc_security_group_ids      = [aws_security_group.kafka.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true # NAT 없이 ECR/외부로 나가기 위함
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  user_data                   = local.ec2_bootstrap

  root_block_device {
    volume_size = var.kafka_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-kafka"
    Role = "kafka" # SSM Run Command 대상 지정에 사용
  }
}

# --- 모니터링 EC2 (Prometheus / Loki / Grafana / Kafka UI) ---
resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.monitoring_instance_type
  subnet_id                   = local.primary_public_subnet_id
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  user_data                   = local.ec2_bootstrap

  root_block_device {
    volume_size = var.monitoring_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-monitoring"
    Role = "monitoring"
  }
}
