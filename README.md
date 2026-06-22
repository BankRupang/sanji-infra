# 산지직경 Terraform 저장소

산지직경 프로젝트 배포를 위한 레포지토리입니다.

인프라 설계(VPC, ALB, ECS Fargate, RDS, ElastiCache, Kafka/모니터링 EC2, ECR, IAM, SSM)를 Terraform 코드로 옮긴 저장소입니다.

## 배포 방법

[DEPLOY.md](docs/DEPLOY.md)를 참고해 주세요.

```bash
terraform init
terraform plan
terraform apply
```

## 파일 구성

- `versions.tf` / `main.tf` : Terraform/프로바이더 설정
- `variables.tf` / `terraform.tfvars.example` : 조정 가능한 값
- `locals.tf` : 서비스 정의표
- `network.tf` / `security_groups.tf` : 네트워크와 방화벽
- `iam.tf` / `ssm.tf` / `ecr.tf` : 권한, 시크릿, 이미지 저장소
- `rds.tf` / `elasticache.tf` : 데이터 계층
- `alb.tf` / `ecs_cluster.tf` / `ecs_services.tf` / `ecs_bid.tf` / `ecs_keycloak.tf` : 컴퓨트
- `ec2.tf` : Kafka, 모니터링 EC2
- `cloudwatch.tf` / `outputs.tf` : 경보와 출력값
