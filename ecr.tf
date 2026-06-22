# ============================================================================
# ECR: 도커 이미지 저장소
# ============================================================================
# 이미지는 ECR에 둡니다. AWS 내부망이라 pull이 빠르고 IAM으로 접근 제어가 됩니다.
# Keycloak은 공개 이미지를 쓰므로 저장소를 만들지 않습니다.

locals {
  # 이미지를 빌드하는 서비스 목록 = 일반 서비스(map) + bid
  ecr_repos = toset(concat(keys(local.services), ["bid-service"]))
}

resource "aws_ecr_repository" "app" {
  for_each = local.ecr_repos

  # 저장소 이름은 "sanji/서비스이름" 형태 (예: sanji/gateway-server)
  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "MUTABLE" # :latest 가변 태그를 덮어쓸 수 있어야 함

  # push할 때 이미지 취약점 자동 스캔
  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true # terraform destroy 시 이미지가 남아 있어도 저장소 삭제 허용
}

# 오래된 이미지가 무한히 쌓이지 않도록, 최근 10개만 남기고 정리합니다.
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
