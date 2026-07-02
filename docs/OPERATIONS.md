# 운영 가이드

배포가 끝난 뒤 일상적으로 하게 되는 작업을 모았습니다.

아래 예시는 모두 운영(prod) 환경 기준입니다. 개발 환경은 이름의 `prod`를 `dev`로 바꾸면 됩니다.
(예: 클러스터 `sanji-prod-cluster` -> `sanji-dev-cluster`)

모든 명령은 AWS CLI 인증이 되어 있어야 동작합니다. (`aws sts get-caller-identity`로 확인)

---

## 1. 서비스 로그 보기

ECS 서비스의 로그는 CloudWatch 로그 그룹에 쌓입니다. 그룹 이름 규칙은 다음과 같습니다.

```
/ecs/sanji-prod/<서비스이름>
```

예를 들어 user-service 로그 그룹은 `/ecs/sanji-prod/user-service`, 입찰 서비스는 `/ecs/sanji-prod/bid-service`, Keycloak은 `/ecs/sanji-prod/keycloak`입니다.

```bash
# 실시간으로 로그 따라 보기 (Ctrl+C로 종료)
aws logs tail /ecs/sanji-prod/user-service --follow --region ap-northeast-2

# 최근 30분 로그만 보기
aws logs tail /ecs/sanji-prod/user-service --since 30m --region ap-northeast-2

# 특정 단어가 들어간 로그만 걸러 보기
aws logs tail /ecs/sanji-prod/order-service --filter-pattern "ERROR" --region ap-northeast-2
```

> 웹 콘솔에서 보고 싶으면 CloudWatch > 로그 그룹에서 위 이름으로 검색하면 됩니다.
> Kafka / 모니터링 EC2의 로그는 CloudWatch가 아니라 EC2 안의 `docker compose logs`로 봅니다. (SSM 접속 방법은 6절)

---

## 2. ECS 서비스 재배포 / 재시작

### 2-1. 같은 이미지로 강제 재시작

코드 변경 없이 태스크만 새로 띄우고 싶을 때(멈춘 서비스 살리기, 설정 새로 읽히기 등) 사용합니다.

```bash
aws ecs update-service \
  --cluster sanji-prod-cluster \
  --service user-service \
  --force-new-deployment \
  --region ap-northeast-2
```

서비스 이름은 로그 그룹과 달리 접두사 없이 `user-service`, `bid-service`, `keycloak`처럼 그대로 씁니다.

### 2-2. 새 코드로 배포하기

새 코드를 배포하는 정식 경로는 **메인 레포(san-ji-jik-kyeng)의 `Deploy ECS` 워크플로우**입니다. `main` 브랜치에 merge하면 자동 실행되고, 특정 서비스만 다시 배포하려면 GitHub Actions에서 수동 실행하며 서비스 이름을 입력합니다.
자세한 배포 흐름은 메인 레포 `docs/CD.md`를 참고해 주세요.

### 2-3. 멈춰버린 태스크 확인

태스크가 자꾸 재시작되면 "왜 멈췄는지(stopped reason)"를 먼저 봅니다.

```bash
# 최근 멈춘 태스크 ARN 조회
aws ecs list-tasks --cluster sanji-prod-cluster --service-name user-service \
  --desired-status STOPPED --region ap-northeast-2

# 멈춘 이유 확인 (위에서 얻은 태스크 ARN 사용)
aws ecs describe-tasks --cluster sanji-prod-cluster --tasks <태스크ARN> \
  --query "tasks[0].stoppedReason" --region ap-northeast-2
```

> 흔한 원인은 "ECR 이미지 없음(CD 미실행)"과 "시크릿이 CHANGE_ME"입니다. 두 경우 모두 [DEPLOY.md](./DEPLOY.md)의 배포/시크릿 단계를 마치면 해결됩니다.

---

## 3. 사양과 대수 조정

부하테스트 결과에 따라 사양을 코드 한 줄로 조정할 수 있습니다. 배포한 환경 폴더(`envs/prod` 또는 `envs/dev`)의 `terraform.tfvars`에 값을 넣고 `terraform apply`만 다시 하면 됩니다.

```hcl
# 예: Redis가 모자라면 한 단계 올리기
redis_node_type = "cache.t3.medium"

# 예: 입찰 서버 최대 대수 늘리기
bid_max_capacity = 8

# 예: Kafka EC2를 고정 사양(m5)으로 교체 (t3 크레딧 소진 시)
kafka_instance_type = "m5.large"
```

자주 바꾸는 변수는 다음과 같습니다.

| 변수 | 조정 대상 |
| --- | --- |
| `db_instance_class` | RDS 사양 |
| `redis_node_type` | Redis 사양 |
| `kafka_instance_type` / `kafka_count` | Kafka EC2 사양 / 대수 |
| `bid_min_capacity` / `bid_max_capacity` | 입찰 서버 오토스케일링 대수 범위 |
| `monitoring_instance_type` | 모니터링 EC2 사양 |

> `apply` 후 실제 반영까지 시간이 걸리는 자원이 있습니다. (RDS 사양 변경은 수 분 이상, 다운타임이 생길 수 있으니 트래픽이 적은 시간에 하세요.)

---

## 4. CloudWatch 경보 대응

`terraform.tfvars`의 `alert_email`을 채우면 아래 경보가 SNS 이메일로 발송됩니다. (비워두면 경보 자원 자체가 만들어지지 않습니다.)

| 경보 이름 | 조건 | 먼저 확인할 것 |
| --- | --- | --- |
| `sanji-prod-alb-5xx` | 5xx 에러율 0.1% 초과 | 어떤 서비스가 에러를 내는지 로그(1절) 확인. 대부분 특정 서비스 장애 |
| `sanji-prod-rds-cpu-high` | RDS CPU 70% 초과 | 느린 쿼리나 커넥션 폭증 여부. 지속되면 `db_instance_class` 상향(3절) |
| `sanji-prod-redis-cpu-high` | Redis CPU 70% 초과 | t3 크레딧도 함께 확인. 지속되면 `redis_node_type` 상향 |
| `sanji-prod-bid-cpu-high` | 입찰 서비스 CPU 70% 초과 | 오토스케일링 최대 대수(`bid_max_capacity`)에 걸렸는지 확인, 필요 시 상향 |
| `sanji-prod-<대상>-credit-low` | t3 CPU 크레딧 잔량 20% 미만 | 아래 설명 참고 |

### t3 크레딧 소진 경보 (`...-credit-low`)

t3 계열(버스터블) 자원은 평소 CPU를 적게 쓰면 "크레딧"을 모아두고, 순간적으로 필요할 때 그 크레딧을 씁니다. 크레딧이 바닥나면 성능이 기준선으로 뚝 떨어집니다. 이 경보는 크레딧이 20% 미만으로 떨어졌을 때 울립니다.

`<대상>` 자리에는 `kafka-1`, `kafka-2`, `kafka-3`, `monitoring`, `redis`, `rds` 중 t3 사양을 쓰는 것이 들어갑니다. 대응 방법은 두 가지입니다.

- **일시적 부하라면**: 부하가 지나가면 크레딧이 다시 쌓이므로 관찰만 합니다.
- **상시 부하라면**: 해당 자원을 고정 사양(m5 등)으로 바꿉니다(3절). 고정 사양으로 바꾸면 크레딧 지표 자체가 사라지고, 경보는 `treat_missing_data = "notBreaching"` 설정 덕분에 자동으로 정상 처리됩니다.

---

## 5. RDS / Redis 직접 접속 (SSM 포트포워딩)

RDS와 Redis는 Private Subnet에 있어 외부에서 직접 접속할 수 없습니다. 별도 Bastion 서버 없이, 이미 떠 있는 모니터링 EC2를 징검다리 삼아 SSM 포트포워딩으로 접속합니다. SSH 키나 별도로 열린 포트 없이 IAM 권한만으로 접속합니다.

```bash
# RDS (기본 로컬 포트 5432)
bash scripts/connect-rds.sh prod
bash scripts/connect-rds.sh prod 15432   # 로컬 포트를 바꾸고 싶을 때

# Redis (기본 로컬 포트 6379)
bash scripts/connect-redis.sh prod
bash scripts/connect-redis.sh prod 16379   # 로컬 포트를 바꾸고 싶을 때
```

세션을 열어둔 채로 다른 터미널에서 접속합니다. RDS는 기본 파라미터 그룹이 SSL을 강제하므로 `sslmode=require`가 필요합니다.

```bash
# 비밀번호 조회
aws ssm get-parameter --name "/sanji/prod/db/password" --with-decryption \
  --region ap-northeast-2 --query "Parameter.Value" --output text

# RDS 접속
psql "host=127.0.0.1 port=<로컬포트> user=sanji dbname=sanji sslmode=require"

# Redis 접속
redis-cli -h 127.0.0.1 -p <로컬포트>
```

접근 통제는 보안 그룹이 아니라 모니터링 EC2에 SSM 세션을 열 수 있는 IAM 권한으로 합니다. 전제 조건은 AWS CLI와 Session Manager 플러그인 설치, 그리고 모니터링 EC2가 실행 중이고 SSM Agent가 Online 상태여야 한다는 것입니다.

---

## 6. Kafka / 모니터링 EC2 접속

EC2 안에서 컨테이너 로그를 보거나 상태를 확인해야 할 때는 SSM 세션으로 들어갑니다. (SSH 아님)

```bash
# 모니터링 EC2 인스턴스 ID 조회
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=monitoring" "Name=tag:Environment,Values=prod" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --region ap-northeast-2 --output text

# 셸 접속 (Role 값을 kafka로 바꾸면 Kafka EC2)
aws ssm start-session --target <인스턴스ID> --region ap-northeast-2
```

접속한 뒤 컨테이너 로그를 봅니다.

```bash
# 예: 모니터링 EC2에서 Grafana/Prometheus 로그
docker compose logs -f prometheus
docker compose logs -f grafana
```

---

## 7. 요금 아끼기

테스트 환경(주로 dev)을 쓰지 않을 때는 통째로 내려두면 요금이 크게 줄어듭니다.

```bash
cd envs/dev
terraform destroy
```

다시 쓸 때는 `terraform apply` 후 메인 레포의 `Deploy EC2` / `Deploy ECS` 워크플로우를 실행하면 됩니다. 전체 복구 절차는 [DEPLOY.md](./DEPLOY.md)의 배포 순서 요약을 참고해 주세요.

주의할 점은 다음과 같습니다.

- **RDS와 Redis의 데이터도 함께 사라집니다.** 중요한 데이터가 있으면 먼저 백업하세요.
- **SSM 파라미터(시크릿)는 destroy로 지워지지 않습니다.** 그래서 재배포해도 채워둔 시크릿 값이 그대로 남아, 시크릿을 다시 입력할 필요가 없습니다.
- 요금 관리를 위해 destroy를 하지만, **실무에서는 prod 환경에서 `deletion_protection`을 켜서 실수 삭제를 막는 것이 권장됩니다.**
