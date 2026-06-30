# ============================================================================
# EC2: Kafka 브로커 3대, 모니터링(PLG) 서버
# ============================================================================

locals {
  ec2_bootstrap = <<-EOT
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker git gettext
    systemctl enable --now docker
    usermod -aG docker ec2-user

    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  EOT
}

resource "aws_instance" "kafka" {
  count                       = 3
  ami                         = var.ami_id
  instance_type               = var.kafka_instance_type
  subnet_id                   = var.primary_public_subnet_id
  vpc_security_group_ids      = [var.sg_kafka_id]
  iam_instance_profile        = var.iam_instance_profile_name
  associate_public_ip_address = true
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  user_data                   = local.ec2_bootstrap

  root_block_device {
    volume_size = var.kafka_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name        = "${var.name}-kafka-${count.index + 1}"
    Role        = "kafka"
    KafkaNodeId = count.index + 1
  }
}

resource "aws_instance" "monitoring" {
  ami                         = var.ami_id
  instance_type               = var.monitoring_instance_type
  subnet_id                   = var.primary_public_subnet_id
  vpc_security_group_ids      = [var.sg_monitoring_id]
  iam_instance_profile        = var.iam_instance_profile_name
  associate_public_ip_address = true
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  user_data                   = local.ec2_bootstrap

  root_block_device {
    volume_size = var.monitoring_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "${var.name}-monitoring"
    Role = "monitoring"
  }
}
