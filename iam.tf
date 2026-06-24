# ============================================================================
# IAM 역할(Role)과 권한
# ============================================================================
# ECS는 Task 역할로, EC2는 Instance 역할로 SSM을 읽습니다.
# 또 GitHub Actions가 키 없이 배포하도록 OIDC 역할을 만듭니다.

# SSM SecureString을 복호화할 때 쓰는 AWS 기본 KMS 키 정보 (조회)
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

# ----------------------------------------------------------------------------
# 1) ECS 태스크 "실행" 역할 (Execution Role)
#    ECS 에이전트가 이미지를 ECR에서 받고, 로그를 쓰고, SSM 시크릿을 읽을 때 씁니다.
# ----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# AWS가 제공하는 기본 정책: ECR pull + CloudWatch Logs 쓰기 권한
resource "aws_iam_role_policy_attachment" "ecs_exec_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# SSM Parameter Store에서 /sanji/* 시크릿을 읽고 복호화하는 추가 권한
data "aws_iam_policy_document" "ecs_secrets" {
  statement {
    sid       = "ReadSanjiParameters"
    actions   = ["ssm:GetParameters", "ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }
  statement {
    sid       = "DecryptWithSsmKey"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }
}

resource "aws_iam_role_policy" "ecs_secrets" {
  name   = "${local.name}-ecs-secrets"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_secrets.json
}

# ----------------------------------------------------------------------------
# 2) ECS 태스크 "작업" 역할 (Task Role)
#    컨테이너 속 앱 코드가 AWS API를 부를 때 쓰는 역할.
#    현재 앱은 AWS를 직접 호출하지 않아 비워두지만, 자리는 만들어 둡니다.
# ----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# ----------------------------------------------------------------------------
# 3) EC2(Kafka, 모니터링) 인스턴스 역할
#    SSM Run Command 수신 + CloudWatch 읽기(Grafana 데이터소스) + SSM 파라미터 읽기
#    EC2는 커스텀 이미지가 없고 퍼블릭 이미지(Docker Hub/ghcr.io)만 사용하므로 ECR 권한 불필요
# ----------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Grafana가 RDS/ElastiCache/ALB 지표를 CloudWatch에서 읽기 위함
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_ro" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# EC2가 시작 스크립트에서 /sanji/* 파라미터(cluster-id, grafana 비밀번호 등)를 읽음
data "aws_iam_policy_document" "ec2_ssm_read" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }
}

resource "aws_iam_role_policy" "ec2_ssm_read" {
  name   = "${local.name}-ec2-ssm-read"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_ssm_read.json
}

# ecs-discovery.sh(cron)가 ECS 태스크 IP를 조회할 때 필요
resource "aws_iam_role_policy" "ec2_ecs_discovery" {
  name = "${local.name}-ec2-ecs-discovery"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "EcsDiscovery"
      Effect   = "Allow"
      Action   = ["ecs:ListTasks", "ecs:DescribeTasks"]
      Resource = "*"
    }]
  })
}

# Grafana CloudWatch datasource가 리전 목록을 조회할 때 필요
resource "aws_iam_role_policy" "ec2_grafana_ec2" {
  name = "${local.name}-ec2-grafana-ec2"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "GrafanaDescribeRegions"
      Effect   = "Allow"
      Action   = ["ec2:DescribeRegions"]
      Resource = "*"
    }]
  })
}

# deploy-monitoring.sh가 RDS 엔드포인트를 조회할 때 필요
resource "aws_iam_role_policy" "ec2_rds_describe" {
  name = "${local.name}-ec2-rds-describe"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RdsDescribeInstances"
      Effect   = "Allow"
      Action   = ["rds:DescribeDBInstances"]
      Resource = "*"
    }]
  })
}

# EC2에 역할을 붙이려면 "인스턴스 프로파일"이라는 포장지가 필요합니다.
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ----------------------------------------------------------------------------
# 4) GitHub Actions OIDC 역할 (CI/CD가 키 없이 배포)
# ----------------------------------------------------------------------------
# OIDC는 "GitHub가 발급한 단기 토큰을 AWS가 믿어주는" 방식입니다.
# 액세스 키를 GitHub Secret에 저장할 필요가 없어 더 안전합니다.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub OIDC 루트 인증서 지문. 바뀌면 GitHub 공지에 따라 갱신하세요.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "github_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    # 토큰 수신자가 STS인지 확인
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # 지정한 GitHub 저장소에서 온 토큰만 신뢰
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count              = var.enable_github_oidc ? 1 : 0
  name               = "${local.name}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json
}

# CI/CD에서 하는 일: ECR push, ECS 롤링 배포 트리거, EC2 배포(SSM), PassRole
data "aws_iam_policy_document" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}/*"]
  }
  # 서비스/태스크 수준 작업: 이 클러스터 안의 리소스로만 범위를 제한합니다.
  statement {
    sid = "EcsDeployService"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${local.name}-cluster/*",
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${local.name}-cluster/*",
    ]
  }
  # RegisterTaskDefinition은 AWS 정책상 특정 리소스로 범위 제한이 불가합니다.
  statement {
    sid = "EcsTaskDefinition"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "Ec2DeployViaSsm"
    actions   = ["ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
  statement {
    sid       = "Ec2DescribeForSsm"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  # ECS 새 태스크가 역할을 쓰려면 CI 역할이 그 역할을 넘겨줄 수 있어야 합니다.
  statement {
    sid       = "PassEcsRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.ecs_task.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  count  = var.enable_github_oidc ? 1 : 0
  name   = "${local.name}-github-actions"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions[0].json
}
