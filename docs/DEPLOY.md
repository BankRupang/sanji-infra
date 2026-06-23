# Terraform 배포 가이드

## 0. Terraform이 뭔가요?

Terraform은 "AWS에 무엇을 만들지를 글(코드)로 적어두면, 그대로 만들어주는 도구"입니다.

- 우리가 `.tf` 파일에 "VPC 1개, RDS 1개, ECS 서비스 11개를 만들어줘"라고 적습니다.
- `terraform apply` 한 번이면 AWS 콘솔을 손으로 클릭하지 않아도 전부 만들어집니다.
- 마음에 안 들면 `terraform destroy`로 한 번에 지웁니다.
- 코드로 남아 있으니, 똑같은 환경을 언제든 다시 만들 수 있습니다.

핵심 명령어 3개만 기억하면 됩니다.

| 명령어 | 하는 일 |
| --- | --- |
| `terraform init` | 필요한 플러그인(AWS용)을 내려받아 준비 |
| `terraform plan` | "이렇게 만들/바꿀 거예요" 미리보기 (실제로 안 만듦) |
| `terraform apply` | 미리보기 내용을 실제로 만듦 |

---

## 1. 사전 준비물

아래 4가지가 준비되어 있어야 합니다.

1. **AWS 계정** 과 결제 수단
2. **Terraform 설치** (v1.10 이상)
   - 확인: `terraform version`
3. **AWS CLI 설치 + 인증**
   - 확인: `aws sts get-caller-identity` 가 내 계정 정보를 보여주면 OK
   - 인증이 안 되어 있으면 `aws configure` 로 액세스 키를 등록하세요.
   - 이 인증 정보로 Terraform이 AWS에 접속합니다.
4. **충분한 IAM 권한**
   - 처음이라면 관리자(AdministratorAccess) 권한 계정으로 하는 게 가장 쉽습니다.
   - 운영에서는 필요한 권한만 따로 부여하세요.

---

## 2. 파일 구조 한눈에 보기

이 폴더의 `.tf` 파일들은 역할별로 나뉘어 있습니다. 한 파일을 다 이해할 필요는 없고, 필요할 때 해당 파일만 열어보면 됩니다.

| 파일 | 내용 |
| --- | --- |
| `versions.tf` | Terraform/AWS 버전 고정, 상태 저장 위치 |
| `main.tf` | 리전 설정, 공통 조회(계정 ID, AMI 등) |
| `variables.tf` | 바꿀 수 있는 값(손잡이) 목록 |
| `terraform.tfvars.example` | 변수 값 예시 (복사해서 채움) |
| `locals.tf` | 서비스 정의표, 공통 환경변수 |
| `network.tf` | VPC, 서브넷, 인터넷 게이트웨이 |
| `security_groups.tf` | 방화벽 규칙 |
| `iam.tf` | 권한 역할 (ECS, EC2, GitHub Actions) |
| `ssm.tf` | 시크릿 보관함(SSM Parameter Store) |
| `ecr.tf` | 도커 이미지 저장소 |
| `rds.tf` | PostgreSQL 데이터베이스 |
| `elasticache.tf` | Redis |
| `alb.tf` | 로드밸런서(외부 진입점) |
| `ecs_cluster.tf` | ECS 클러스터 + 서비스 디스커버리 |
| `ecs_services.tf` | 일반 서비스 9개 |
| `ecs_bid.tf` | 입찰 서비스 + 오토스케일링 |
| `ecs_keycloak.tf` | 인증 서버 |
| `ec2.tf` | Kafka, 모니터링 EC2 |
| `cloudwatch.tf` | 기본 경보 |
| `outputs.tf` | 끝나고 보여줄 접속 주소들 |

---

## 3. 변수 값 채우기

`terraform.tfvars.example` 파일을 복사해 `terraform.tfvars` 를 만들고 값을 채웁니다.
(`terraform.tfvars` 는 비밀번호가 들어가므로 git에 올라가면 안됩니다.)

```bash
cd .terraform
cp terraform.tfvars.example terraform.tfvars
```

그다음 `terraform.tfvars` 를 열어 최소한 아래 2개는 꼭 채웁니다.

```hcl
db_password = "강력한-비밀번호"          # 필수
admin_cidr  = "내-공인IP/32"            # Grafana/SSH 접근 IP. 예: "1.2.3.4/32"
```

> `admin_cidr` 를 `0.0.0.0/0`(전체 허용)로 두면 전 세계 누구나 Grafana 로그인 화면에 접근할 수 있습니다. 본인 IP로 꼭 좁히세요. (본인 IP 확인: 검색창에 "내 IP")

---

## 4. 인프라 만들기 (apply)

```bash
# 1) 플러그인 준비 (최초 1회, 또는 버전 바꿀 때)
terraform init

# 2) 미리보기: 무엇이 만들어지는지 확인 (실제로는 아직 안 만듦)
terraform plan

# 3) 실제로 만들기: "yes" 를 입력하면 시작
terraform apply
```

`apply` 는 10~20분 정도 걸립니다. (RDS와 ElastiCache 생성이 오래 걸립니다.)
다 끝나면 화면 맨 아래에 접속 주소들이 출력됩니다. 다시 보고 싶으면:

```bash
terraform output
```

> 이 시점에는 "그릇"만 만들어진 상태입니다. ECS 서비스들은 아직 도커 이미지가 없어서 정상 기동하지 못합니다. 아래 5~7단계를 마쳐야 실제로 동작합니다.

---

## 5. apply 후 꼭 해야 하는 마무리 작업

Terraform은 시크릿(비밀번호, API 키)을 안전하게 다루려고, DB 비밀번호 말고는
**빈 칸("CHANGE_ME")** 으로만 만들어 둡니다. 실제 값은 아래처럼 직접 채웁니다.

### 5-1. 앱 시크릿 실제 값 채우기

```bash
REGION=ap-northeast-2

# 예시: Gemini API 키
aws ssm put-parameter --overwrite --type SecureString --region $REGION \
  --name /sanji/prod/ai/gemini-api-key --value "진짜-키-값"

# 나머지도 같은 방식으로 채웁니다. (값이 없는 항목은 건너뛰어도 됩니다)
#   /sanji/prod/keycloak/client-secret
#   /sanji/prod/keycloak/admin-password
#   /sanji/prod/user/manager-key
#   /sanji/prod/user/master-key
#   /sanji/prod/toss/client-key
#   /sanji/prod/toss/secret-key
#   /sanji/prod/slack/webhook-url
#   /sanji/prod/slack/bot-token
```

> `--overwrite` 를 써도 Terraform은 이 값을 다시 덮어쓰지 않습니다.
> (코드에 `ignore_changes` 가 걸려 있어 사람이 채운 값을 그대로 둡니다.)

### 5-2. EC2용 시크릿 채우기

```bash
# Kafka Cluster ID (최초 1회만 생성, 이후 같은 값 유지)
CLUSTER_ID=$(docker run --rm apache/kafka:3.7.0 \
  /opt/kafka/bin/kafka-storage.sh random-uuid)
aws ssm put-parameter --overwrite --type SecureString --region $REGION \
  --name /sanji/prod/kafka/cluster-id --value "$CLUSTER_ID"

# Grafana 관리자 비밀번호
aws ssm put-parameter --overwrite --type SecureString --region $REGION \
  --name /sanji/prod/monitoring/grafana-admin-password --value "원하는-비밀번호"

# Grafana 알림용 Slack Webhook (선택)
aws ssm put-parameter --overwrite --type SecureString --region $REGION \
  --name /sanji/prod/monitoring/slack-webhook-url --value "https://hooks.slack.com/..."

# Langfuse (LLM 트레이싱) 시크릿 (각각 랜덤 문자열 생성)
NEXTAUTH_SECRET=$(openssl rand -base64 32)
SALT=$(openssl rand -base64 32)
aws ssm put-parameter --overwrite --type SecureString --region $REGION \
  --name /sanji/prod/langfuse/nextauth-secret --value "$NEXTAUTH_SECRET"
aws ssm put-parameter --overwrite --type SecureString --region $REGION \
  --name /sanji/prod/langfuse/salt --value "$SALT"
```

> Kafka 사설 IP(`/sanji/prod/kafka/private-ip`)는 Terraform이 자동으로 채워두므로
> 직접 등록할 필요가 없습니다.

### 5-3. 데이터베이스 스키마 만들기

앱은 서비스별 스키마(`user_schema` 등)를 씁니다. RDS에 스키마와 pgvector 확장을 만듭니다.
RDS는 프라이빗 서브넷에 있으므로, 같은 VPC 안의 EC2(예: 모니터링 EC2)에서 접속합니다.

```bash
# RDS 주소는 terraform output rds_endpoint 로 확인
psql "host=<RDS주소> port=5432 dbname=sanji user=sanji" -f db/init/init-schemas.sql

# AI 벡터 검색용 확장 (한 번만)
psql "host=<RDS주소> port=5432 dbname=sanji user=sanji" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

---

## 6. 도커 이미지 ECR로 올리기

ECS 서비스가 받아쓸 이미지를 ECR에 올립니다. 보통은 GitHub Actions(8단계)가 자동으로 하지만, 처음 한 번은 수동으로 올려 서비스를 띄울 수 있습니다.

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# ECR 로그인
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $REGISTRY

# 예시: gateway-server 이미지 빌드 후 push
docker build -t $REGISTRY/sanji/gateway-server:latest \
  -f gateway-server/Dockerfile .
docker push $REGISTRY/sanji/gateway-server:latest

# 나머지 서비스도 같은 방식으로 (config-server, discovery-server, user-service,
# auction-service, bid-service, order-service, payment-service,
# notification-service, ai-service)
```

이미지가 올라가면 ECS가 자동으로 다시 받아 태스크를 정상 기동합니다. (조금 기다리면 됩니다.)

---

## 7. Kafka / 모니터링 EC2 배포

> **자동화 완료**: 아래 작업은 GitHub Actions `Deploy EC2` 워크플로우가 자동으로 수행합니다.
> `main` 브랜치에 코드가 합쳐지면 자동 실행되고, 수동으로 돌리려면 워크플로우 페이지에서 `workflow_dispatch`를 누르면 됩니다.
> 직접 실행할 필요는 없습니다.

(참고) 워크플로우 내부에서 하는 일:

```bash
# Kafka EC2
cd /home/ec2-user/sanji-jk
git pull origin main
docker compose -f docker-compose.kafka.yml pull
docker compose -f docker-compose.kafka.yml up -d

# 모니터링 EC2
git pull origin main
# SSM에서 Kafka IP를 읽어 prometheus.prod.yml에 채움
KAFKA_PRIVATE_IP=$(aws ssm get-parameter --name /sanji/prod/kafka/private-ip ...)
export KAFKA_PRIVATE_IP
envsubst '$KAFKA_PRIVATE_IP' < prometheus.prod.yml.template > prometheus.prod.yml
docker compose -f docker-compose.monitoring.yml pull
docker compose -f docker-compose.monitoring.yml up -d
# prometheus.prod.yml은 바인드 마운트 파일이라 up -d만으로는 Prometheus가 새 설정을 읽지 않음
docker compose -f docker-compose.monitoring.yml restart prometheus
```

접속 주소는 `terraform output` 에 나옵니다.

| 화면 | 주소 |
| --- | --- |
| 서비스(앱) | `terraform output alb_dns_name` |
| Grafana | `terraform output grafana_url` |
| Prometheus | `terraform output prometheus_url` |

---

## 8. GitHub Actions 연동 (CI/CD)

Terraform이 GitHub Actions용 역할을 미리 만들어 둡니다. 액세스 키 없이도 안전하게 배포할 수 있습니다.

1. 역할 ARN을 확인합니다.
   ```bash
   terraform output github_actions_role_arn
   ```
2. GitHub 저장소 > Settings > Secrets and variables > Actions > **Variables** 탭에서
   `AWS_ROLE_ARN` 이름으로 위 ARN 값을 등록합니다.
   (워크플로우가 `${{ vars.AWS_ROLE_ARN }}`으로 이 값을 참조합니다.)
3. 이후 `main` 브랜치 push 시 ECS 배포, EC2 모니터링 배포가 키 없이 자동 실행됩니다.

**ECS 배포 흐름 (wave 구조):**

ECS 서비스 10개를 한 번에 배포하면 Fargate vCPU 한도(30)를 초과합니다. 그래서 3개 wave로 나눠 순서대로 배포합니다.

```
build → wave-1(config/discovery/gateway) → wave-2(user/auction/order/payment) → wave-3(bid/notification/ai)
```

wave 안에서는 서비스들이 동시에 배포됩니다. 특정 wave가 실패하면 Actions UI에서 그 wave만 재실행할 수 있습니다.

> 다른 저장소 이름을 쓰면 `terraform.tfvars` 의 `github_repo` 값을 맞춰 바꾼 뒤
> `terraform apply` 하세요.

---

## 9. 사양/대수 바꾸기 (variable로 조정)

문서 방침대로, 부하테스트 결과에 따라 사양을 코드 한 줄로 조정합니다.
`terraform.tfvars` 에 값을 적고 `terraform apply` 만 다시 하면 됩니다.

```hcl
# 예: Redis가 모자라면 한 단계 올리기
redis_node_type = "cache.t3.medium"

# 예: 입찰 서버 최대 대수 늘리기
bid_max_capacity = 8

# 예: Kafka EC2를 고정 사양(m5)으로 교체 (t3 크레딧 소진 시)
kafka_instance_type = "m5.large"
```

---

## 10. HTTPS 켜기 (선택)

기본은 HTTP만 동작합니다. 도메인과 ACM 인증서가 있으면 HTTPS를 켤 수 있습니다.

1. ACM에서 인증서를 발급받습니다. (ap-northeast-2 리전)
2. `terraform.tfvars` 에 ARN을 넣습니다.
   ```hcl
   acm_certificate_arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/xxxx"
   ```
3. `terraform apply` 하면 443 리스너가 생기고, 80 요청은 443으로 자동 리다이렉트됩니다.

---

## 11. 전부 지우기 (destroy)

연습이 끝났거나 비용을 멈추고 싶으면 한 번에 지웁니다.

```bash
terraform destroy
```

> 주의: RDS와 Redis의 데이터도 함께 사라집니다. 중요한 데이터가 있으면 먼저 백업해야 합니다.
> (운영에서는 `rds.tf` 의 `deletion_protection` 을 `true` 로 두어 실수 삭제를 막아야 합니다.)

---

## 12. 자주 겪는 문제

| 증상 | 원인 / 해결 |
| --- | --- |
| `apply` 가 권한 오류로 멈춤 | AWS CLI 인증 계정의 IAM 권한 부족. 관리자 권한으로 시도 |
| ECS 태스크가 계속 재시작됨 | 아직 ECR 이미지가 없거나(6단계), 시크릿이 CHANGE_ME(5단계). 둘 다 채우면 안정화됨 |
| 앱이 DB 접속 실패 | RDS 스키마 미생성(5-3단계) 또는 보안 그룹 점검 |
| Grafana 접속 안 됨 | `admin_cidr` 가 내 IP를 포함하는지 확인 |
| GitHub OIDC 신뢰 오류 | `github_repo` 값이 실제 "조직/저장소"와 같은지 확인 |
| RDS 버전 오류 | `db_engine_version` 을 현재 RDS가 지원하는 버전으로 조정 |
| Prometheus ECS 타겟 전부 Down | cron 미실행 가능성. EC2에서 `cat /home/ec2-user/ecs-discovery.log` 로 확인. 로그가 없으면 cron 등록 실패. `Deploy EC2` 워크플로우 재실행으로 cron 재등록 |
| Prometheus kafka 타겟 Down | `prometheus.prod.yml` 에 Kafka IP가 비어 있을 경우. `Deploy EC2` 워크플로우 재실행 시 자동 수정됨 |
| Spring Boot Actuator `/actuator/prometheus` 401 | gateway-server `SecurityConfig.java` 에 해당 경로가 `permitAll()` 에 포함되어 있는지 확인 |

---

## 13. 배포 순서 요약 (체크리스트)

1. [ ] `bootstrap/` 폴더에서 S3 버킷 생성: `cd bootstrap && terraform init && terraform apply`
2. [ ] `terraform.tfvars` 작성 (`db_password`, `admin_cidr`)
3. [ ] `terraform init` (S3로 상태 이전 여부 물으면 `yes`)
4. [ ] `terraform apply`
5. [ ] SSM 시크릿 실제 값 채우기 (5-1, 5-2)
6. [ ] RDS 스키마 + pgvector 생성 (5-3)
7. [ ] 도커 이미지 ECR push (6단계, 또는 GitHub Actions)
8. [ ] Kafka / 모니터링 EC2 배포 (7단계)
9. [ ] `terraform output` 으로 접속 주소 확인
10. [ ] GitHub Actions `AWS_ROLE_ARN` Variable 등록 (8단계)
