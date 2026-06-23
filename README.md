# 산지직경 Terraform 저장소

산지직경 프로젝트 배포를 위한 레포지토리입니다.

인프라 설계(VPC, ALB, ECS Fargate, RDS, ElastiCache, Kafka/모니터링 EC2, ECR, IAM, SSM)를 Terraform 코드로 옮긴 저장소입니다.

## 배포 방법

자세한 내용은 [DEPLOY.md](docs/DEPLOY.md)를 참고해 주세요.

S3 backend를 먼저 만들어야 합니다. `bootstrap/` 폴더를 먼저 실행합니다.

```bash
# 1) S3 버킷 + DynamoDB 테이블 생성 (최초 1회)
cd bootstrap
terraform init && terraform apply
cd ..

# 2) 본 인프라 배포
terraform init    # "로컬 상태를 S3로 옮길까요?" → yes
terraform plan
terraform apply
```

## 파일 구성

```
.terraform/
  bootstrap/          S3 버킷 + DynamoDB 테이블 (최초 1회 실행)
  docs/DEPLOY.md      단계별 배포 가이드
  versions.tf         Terraform/프로바이더 버전 고정, S3 backend 설정
  main.tf             리전 설정, 공통 데이터 조회
  variables.tf        조정 가능한 값 목록
  terraform.tfvars.example  변수 값 예시
  locals.tf           서비스 정의표 (ECS 서비스 9개 한 곳에서 관리)
  network.tf          VPC, 서브넷, 인터넷 게이트웨이
  security_groups.tf  방화벽 규칙
  iam.tf              권한 역할 (ECS, EC2, GitHub Actions OIDC)
  ssm.tf              시크릿 보관함
  ecr.tf              도커 이미지 저장소
  rds.tf              PostgreSQL
  elasticache.tf      Redis
  alb.tf              로드밸런서
  ecs_cluster.tf      ECS 클러스터 + 서비스 디스커버리
  ecs_services.tf     일반 서비스 9개 (for_each)
  ecs_bid.tf          입찰 서비스 + 오토스케일링
  ecs_keycloak.tf     인증 서버
  ec2.tf              Kafka, 모니터링 EC2
  cloudwatch.tf       CloudWatch 경보
  outputs.tf          배포 후 접속 주소 출력
```
