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
   - AWS 콘솔에서 IAM 사용자와 액세스 키를 먼저 생성해야 합니다. [(참고)](https://munsik22.tistory.com/350)
   - 확인: `aws sts get-caller-identity` 가 내 계정 정보를 보여주면 OK
   - 인증이 안 되어 있으면 `aws configure` 로 액세스 키를 등록해주세요.
   - 이 인증 정보로 Terraform이 AWS에 접속합니다.
4. **충분한 IAM 권한**
   - 처음이라면 관리자(AdministratorAccess) 권한 계정으로 하는 게 가장 쉽습니다.
   - 운영에서는 필요한 권한만 따로 부여하세요.

---

## 2. 변수 값 채우기

배포할 환경 폴더로 이동한 뒤 `terraform.tfvars.example` 파일을 복사해 `terraform.tfvars` 를 만들고 값을 채웁니다.
(`terraform.tfvars` 는 비밀번호가 들어가므로 git에 올라가면 안됩니다.)

```bash
# 운영(prod) 배포라면
cd .terraform/envs/prod
cp terraform.tfvars.example terraform.tfvars

# 개발(dev) 배포라면
cd .terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars
```

그다음 `terraform.tfvars` 를 열어 최소한 아래 2개는 꼭 채웁니다.

```hcl
db_password = "강력한-비밀번호"          # 필수
admin_cidr  = "내-공인IP/32"            # Grafana/SSH 접근 IP. 예: "1.2.3.4/32"
```

> `admin_cidr` 를 `0.0.0.0/0`(전체 허용)로 두면 전 세계 누구나 Grafana 로그인 화면에 접근할 수 있습니다. 본인 IP로 꼭 좁히세요. (본인 IP 확인: 검색창에 "내 IP")

---

## 3. 인프라 만들기 (apply)

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

> 이 시점에는 그릇만 만들어진 상태입니다. ECS 서비스들은 아직 도커 이미지가 없어서 정상 기동하지 못합니다. 아래 4~5단계를 마쳐야 실제로 동작합니다.

---

## 4. SSM 파라미터 값 주입

`bootstrap apply`에서 시크릿 파라미터들을 **"CHANGE_ME"** 로 미리 만들어 두었습니다.
(DB 비밀번호는 `terraform.tfvars`로 메인 apply 때 자동 등록됩니다.)
아래 순서로 실제 값을 채웁니다. (최초 1회만 하면 됩니다.)

```bash
# 1) 파라미터 경로가 미리 채워진 JSON 템플릿 생성
bash scripts/ssm-init.sh

# 2) 생성된 scripts/ssm-backup.json을 열어 CHANGE_ME를 실제 값으로 교체
#    (없는 항목은 CHANGE_ME로 두면 ssm-restore.sh가 건너뜁니다)

# 3) AWS에 일괄 등록
bash scripts/ssm-push.sh
```

파라미터 경로와 내용은 다음과 같습니다.

| 파라미터 경로 | 내용 |
| --- | --- |
| `/sanji/prod/keycloak/client-secret` | Keycloak 클라이언트 시크릿 (6-3단계 이후 자동 발급) |
| `/sanji/prod/keycloak/admin-password` | Keycloak 관리자 비밀번호 |
| `/sanji/prod/user/manager-key` | 사용자 서비스 매니저 키 |
| `/sanji/prod/user/master-key` | 사용자 서비스 마스터 키 |
| `/sanji/prod/toss/client-key` | Toss Payments 클라이언트 키 |
| `/sanji/prod/toss/secret-key` | Toss Payments 시크릿 키 |
| `/sanji/prod/slack/webhook-url` | Slack Webhook URL |
| `/sanji/prod/slack/bot-token` | Slack 봇 토큰 |
| `/sanji/prod/ai/gemini-api-key` | Gemini API 키 |
| `/sanji/prod/kafka/cluster-id` | Kafka Cluster ID (임의의 UUID 값) |
| `/sanji/prod/monitoring/grafana-admin-password` | Grafana 관리자 비밀번호 |
| `/sanji/prod/monitoring/slack-webhook-url` | Grafana 알림용 Slack Webhook |
| `/sanji/prod/langfuse/nextauth-secret` | Langfuse NextAuth 시크릿 (`openssl rand -base64 32`으로 생성) |
| `/sanji/prod/langfuse/salt` | Langfuse Salt (`openssl rand -base64 32`으로 생성) |

> `ssm-backup.json`에 시크릿이 담기므로 git에 올리지 마세요.
> Terraform은 한 번 채운 값을 다시 덮어쓰지 않습니다. (`ignore_changes` 설정)

---

## 5. Kafka / 모니터링 EC2 배포

> GitHub Actions `Deploy EC2` 워크플로우가 자동으로 수행합니다.
> `main` 브랜치에 코드가 합쳐지면 자동 실행됩니다. 수동으로 돌리려면 워크플로우 페이지에서 `workflow_dispatch`를 눌러주세요.

접속 주소는 `terraform output` 에 나옵니다.

| 화면 | 주소 |
| --- | --- |
| 서비스(앱) | `terraform output alb_dns_name` |
| Grafana | `terraform output grafana_url` |
| Prometheus | `terraform output prometheus_url` |

---

## 6. 초기 설정 스크립트 (최초 배포 시 1회)

EC2가 올라온 뒤 아래 3개 스크립트를 순서대로 실행합니다. 모두 AWS CLI 인증이 되어 있으면 로컬에서 실행할 수 있습니다.

### 6-1. RDS 스키마 초기화

별도 수동 실행이 필요 없습니다. 모두 자동으로 처리됩니다.

| 대상 | 처리 주체 | 시점 |
| --- | --- | --- |
| keycloak/langfuse 스키마 | Terraform `null_resource` | `terraform apply` 시 |
| Spring 서비스 스키마 (`user_schema` 등) | Flyway `create-schemas: true` | 각 서비스 첫 기동 시 |
| pgvector 확장 | Spring AI `initialize-schema: true` | ai-service 첫 기동 시 |

문제가 생겼을 때 수동 복구가 필요한 경우에만 `bash scripts/db-init.sh`를 사용합니다.

### 6-2. Keycloak 설정

별도 수동 실행이 필요 없습니다. Deploy EC2 워크플로우가 자동으로 처리합니다.

| 처리 주체 | 시점 | 동작 |
| --- | --- | --- |
| Deploy EC2 워크플로우 (메인 레포) | 모니터링 EC2 배포 직후 | realm import + client-secret 발급 + SSM 저장 |

멱등 처리: sanjijk realm이 이미 Keycloak DB에 있으면 건너뜁니다. terraform destroy 후 재배포 시에만 실제로 동작합니다.

완료 후: GitHub Actions `Deploy ECS`를 수동으로 한 번 더 실행해 새 client-secret을 반영합니다.

### 6-3. 관리자가 RDS/Redis 직접 조작하기 (SSM 포트포워딩)

RDS와 Redis는 Private Subnet에 있어 외부에서 직접 접속할 수 없습니다. 모니터링 EC2를 징검다리 삼아 SSM 포트포워딩으로 접속합니다. 구체적인 접속 방법은 운영 가이드로 옮겼습니다. [OPERATIONS.md의 "RDS / Redis 직접 접속"](./OPERATIONS.md#5-rds--redis-직접-접속-ssm-포트포워딩)을 참고해 주세요.

---

## 7. 사양/대수 바꾸기 (variable로 조정)

부하테스트 결과에 따라 사양을 코드 한 줄로 조정할 수 있습니다. `terraform.tfvars`에 값을 수정하고 `terraform apply`만 다시 하면 됩니다. 조정 가능한 변수 목록과 예시는 [OPERATIONS.md의 "사양과 대수 조정"](./OPERATIONS.md#3-사양과-대수-조정)을 참고해 주세요.

---

## 8. HTTPS 켜기 (선택)

기본은 HTTP만 동작합니다. 도메인과 ACM 인증서가 있으면 HTTPS를 켤 수 있습니다.

1. ACM에서 인증서를 발급받습니다. (ap-northeast-2 리전)
2. `terraform.tfvars` 에 ARN을 넣습니다.
   ```hcl
   acm_certificate_arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/xxxx"
   ```
3. `terraform apply` 하면 443 리스너가 생기고, 80 요청은 443으로 자동 리다이렉트됩니다.

---

## 9. 전부 지우기 (destroy)

테스트가 끝났거나 과금을 멈추고 싶으면 한 번에 지웁니다.

```bash
terraform destroy
```

> 주의: RDS와 Redis의 데이터도 함께 사라집니다. 중요한 데이터가 있으면 먼저 백업해야 합니다.
> SSM 파라미터는 destroy로 지워지지 않습니다. destroy 후 재배포해도 기존에 채워둔 시크릿 값이 그대로 남아 있습니다.
> (운영에서는 `rds.tf` 의 `deletion_protection` 을 `true` 로 두어 실수 삭제를 막아야 합니다.)

---

## 10. SSM 파라미터 백업 / 복구

다른 AWS 계정이나 환경으로 시크릿을 옮겨야 할 때 사용합니다. 일반적인 destroy/재배포에는 필요 없습니다.

```bash
# 현재 SSM 파라미터 값을 파일로 내보내기
bash scripts/ssm-pull.sh      # scripts/ssm-backup.json 생성 (시크릿 포함, git에 올리지 마세요)

# 파일에서 SSM 파라미터 값 복구 (CHANGE_ME 항목과 kafka/private-ip는 건너뜀)
bash scripts/ssm-push.sh
```

---

## 11. 자주 겪는 문제

| 증상 | 원인 / 해결 |
| --- | --- |
| `apply` 가 권한 오류로 멈춤 | AWS CLI 인증 계정의 IAM 권한 부족. 관리자 권한으로 시도 |
| ECS 태스크가 계속 재시작됨 | ECR 이미지가 없거나(CI/CD 미실행), 시크릿이 CHANGE_ME(4단계). 둘 다 채우면 안정화됨 |
| Grafana 접속 안 됨 | `admin_cidr` 가 내 IP를 포함하는지 확인 |
| GitHub OIDC 신뢰 오류 | `github_repo` 값이 실제 "조직/저장소"와 같은지 확인 |
| RDS 버전 오류 | `db_engine_version` 을 현재 RDS가 지원하는 버전으로 조정 |
| Prometheus ECS 타겟 전부 Down | cron 미실행 가능성. EC2에서 `cat /home/ec2-user/ecs-discovery.log` 로 확인. 로그가 없으면 cron 등록 실패. `Deploy EC2` 워크플로우 재실행으로 cron 재등록 |
| Prometheus kafka 타겟 Down | `Deploy EC2` 워크플로우 재실행 시 자동 수정됨. `too many colons in address` 에러가 보이면 SSM `kafka/private-ip` 값이 포트 포함 형식으로 남아 있는 것이므로 `terraform apply` 후 워크플로우 재실행 |
| Spring Boot Actuator `/actuator/prometheus` 401 | gateway-server `SecurityConfig.java` 에 해당 경로가 `permitAll()` 에 포함되어 있는지 확인 |
| `apply` 시 `/bin/bash` 없다는 에러 | Windows에서 로컬 실행 시 발생. `terraform.tfvars` 에 `bash_path = "C:/Program Files/Git/bin/bash.exe"` 추가 |
| Deploy EC2 워크플로우에서 `ecs:ListTasks` AccessDeniedException | `terraform apply` 로 IAM 정책을 최신 상태로 반영한 뒤 워크플로우 재실행 |
| Deploy EC2 kafka 배포에서 `ec2:DescribeTags` UnauthorizedOperation | Kafka EC2 인스턴스 역할에 `ec2:DescribeTags` 권한 미포함. `terraform apply` 로 IAM 정책을 최신 상태로 반영한 뒤 워크플로우 재실행 |

---

## 12. 배포 순서 요약 (체크리스트)

1. [ ] `bootstrap/` 폴더에서 S3 버킷 + SSM 파라미터 생성: `cd .terraform/bootstrap && terraform init && terraform apply`
2. [ ] 환경 폴더로 이동: `cd .terraform/envs/prod` (또는 `envs/dev`)
3. [ ] `terraform.tfvars` 작성 (`db_password`, `admin_cidr`)
4. [ ] `terraform init`
5. [ ] `terraform apply`
6. [ ] SSM 시크릿 실제 값 채우기 (4-1, 4-2)
7. [ ] Kafka / 모니터링 EC2 배포 (5단계, GitHub Actions 자동 실행)
8. [ ] RDS 스키마 초기화 확인 (keycloak/langfuse: terraform apply 시 자동, Spring 서비스: 각 서비스 기동 시 자동, pgvector: ai-service 기동 시 자동)
9. [ ] Deploy EC2 워크플로우가 Keycloak realm + client-secret 자동 처리 (8번에 포함)
10. [ ] GitHub Actions `Deploy ECS` 수동 실행 (keycloak client-secret 반영)
11. [ ] `terraform output` 으로 접속 주소 확인
