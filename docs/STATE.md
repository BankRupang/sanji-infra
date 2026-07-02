# Terraform state 관리

state는 Terraform에서 사고가 가장 잦은 부분입니다. 이 문서는 "state가 무엇인지"부터 "꼬였을 때 어떻게 되돌리는지"까지 설명합니다.

---

## 1. state가 무엇인가요?

Terraform은 "코드에 적힌 자원"과 "실제 AWS에 만들어진 자원"을 연결하는 장부를 하나 들고 있습니다. 이 장부가 **state**입니다.

예를 들어 코드에 `aws_db_instance.main`이라고 적혀 있으면, state에는 "그 코드가 실제로는 `sanji-prod-postgres`라는 RDS 인스턴스다"라는 매핑이 저장됩니다. `terraform plan`은 다음 세 가지를 비교해서 무엇을 만들고 바꿀지 계산합니다.

```
코드(.tf)  <->  state(장부)  <->  실제 AWS
```

그래서 state가 실제와 어긋나면, Terraform이 "이미 있는 걸 또 만들려고" 하거나 "이미 지운 걸 지우려고" 해서 문제가 생깁니다.

---

## 2. 이 프로젝트의 state 구조

state를 로컬 PC에 두면 팀원끼리 공유가 안 되고, 파일을 잃어버리면 장부가 통째로 사라집니다. 그래서 **S3에 원격으로 보관**합니다.

| 항목 | 값 |
| --- | --- |
| S3 버킷 | `sanji-terraform-state` |
| prod state 위치(key) | `prod/terraform.tfstate` |
| dev state 위치(key) | `dev/terraform.tfstate` |
| 리전 | `ap-northeast-2` |
| 암호화 | 켜짐 (`encrypt = true`) |

설정은 각 환경 폴더의 `versions.tf` 안 `backend "s3"` 블록에 있습니다. prod와 dev가 **같은 버킷을 쓰되 key(폴더 경로)로 분리**되어, 두 환경의 장부가 섞이지 않습니다.

버킷 자체는 bootstrap이 만들며, 버전 관리가 켜져 있어 state가 실수로 덮어써져도 이전 버전으로 되돌릴 수 있습니다.

---

## 3. bootstrap의 state는 로컬 파일입니다 (주의)

환경(prod/dev)의 state는 S3에 있지만, **bootstrap 폴더의 state는 로컬 파일**(`bootstrap/terraform.tfstate`)입니다.

state를 담을 S3 버킷을 만드는 것이 bootstrap의 역할인데, 그 버킷이 아직 없는 상태에서 자기 state를 S3에 둘 수는 없기 때문입니다.

이 때문에 다음을 주의해야 합니다.

- **PC가 바뀌거나 `bootstrap/terraform.tfstate` 파일을 잃어버리면** bootstrap이 만든 자원(S3 버킷, 시크릿 파라미터)을 Terraform이 더 이상 추적하지 못합니다.
- 다만 bootstrap 자원에는 `prevent_destroy = true`가 걸려 있어 실제 AWS 자원은 **삭제되지 않고 그대로 남아 있습니다.** 즉 장부만 잃는 것이지 실물이 사라지는 것은 아닙니다.
- bootstrap은 **최초 1회만 실행**하는 폴더라, 평소 운영에서는 이 state를 건드릴 일이 거의 없습니다.

### bootstrap state를 잃었을 때

버킷과 시크릿은 AWS에 그대로 있으므로, `terraform apply`를 다시 하면 "이미 있는 이름"이라 충돌이 납니다. 이럴 때는 새로 만들지 말고, 기존 자원을 state로 다시 끌어옵니다. (5-3절 `import` 참고)

> 팀으로 작업한다면 `bootstrap/terraform.tfstate`를 안전한 공용 위치(예: 비공개 저장소)에 보관해 두는 것을 권장합니다. 단, 이 파일에도 시크릿 관련 정보가 담길 수 있으니 git에는 올리지 마세요.

---

## 4. 동시 apply 방지 (잠금)

두 사람이 같은 환경을 동시에 `apply`하면 장부가 서로 덮어써져 깨집니다. 이를 막기 위해 **state 잠금**을 씁니다.

이 프로젝트는 `use_lockfile = true` 설정으로 **S3가 직접 잠금 파일을 관리**합니다. (Terraform 1.10부터 지원되며, 예전처럼 DynamoDB 테이블을 따로 둘 필요가 없습니다.) 누군가 `apply` 중이면 다른 사람의 `apply`는 잠금이 풀릴 때까지 대기합니다.

운영 규칙으로 다음을 지키면 사고를 크게 줄일 수 있습니다.

- 한 환경에 대한 `apply`는 한 번에 한 사람만 합니다.
- `apply` 전에는 항상 `terraform plan`으로 무엇이 바뀌는지 먼저 확인합니다.
- CI/CD 파이프라인과 사람이 동시에 같은 환경을 건드리지 않도록 시점을 조율합니다.

> 만약 `apply`가 중간에 강제 종료되어 잠금이 남아버리면, 다음 실행 시 잠금 오류가 납니다. 정말 아무도 실행 중이 아님을 확인한 뒤에만 `terraform force-unlock <LOCK_ID>`로 해제하세요. (실행 중인데 풀면 state가 깨집니다.)

---

## 5. state가 실제와 달라졌을 때 복구

콘솔에서 자원을 손으로 지우거나 바꾸면 state와 실제가 달라집니다. 아래 명령으로 진단하고 되돌립니다. 모두 배포한 환경 폴더(`envs/prod` 등) 안에서 실행합니다.

### 5-1. 무엇이 장부에 있는지 보기

```bash
# state에 기록된 자원 목록
terraform state list

# 특정 자원의 상세 정보
terraform state show 'module.data.aws_db_instance.main'
```

### 5-2. 실제와 다시 맞추기 (refresh)

콘솔에서 바뀐 실제 상태를 장부에 반영만 하고 싶을 때 씁니다.

```bash
terraform plan -refresh-only    # 무엇이 달라졌는지 미리보기
terraform apply -refresh-only   # 장부를 실제에 맞춰 갱신
```

### 5-3. 자원을 장부에서 빼거나(rm) 다시 넣기(import)

- **`terraform state rm`**: 실제 AWS 자원은 그대로 두고, 장부에서만 뺍니다. (Terraform이 더 이상 관리하지 않게 됨)
- **`terraform import`**: 이미 AWS에 있는 자원을 장부에 다시 등록합니다. (3절 bootstrap 복구가 대표 사례)

```bash
# 예: 장부에서만 제거 (실제 자원은 유지)
terraform state rm 'module.data.aws_db_instance.main'

# 예: 실제 자원을 장부에 다시 등록 (코드 주소 <- 실제 ID)
terraform import 'aws_s3_bucket.tf_state' sanji-terraform-state
```

> `import`는 코드에 해당 자원 블록이 이미 있어야 동작합니다. 없으면 먼저 코드를 작성한 뒤 import 하세요.

---

## 6. 하지 말아야 할 것

- **S3의 state 파일을 손으로 편집하지 마세요.** 장부가 깨지면 `plan`/`apply`가 엉뚱한 동작을 합니다. 꼭 필요하면 위의 `state` 명령으로만 다루세요.
- **state 파일을 git에 올리지 마세요.** 안에 DB 주소나 시크릿 값이 평문으로 들어갈 수 있습니다. (`.gitignore`에 `*.tfstate`가 이미 등록되어 있습니다.)
- **환경 폴더에서 backend 설정(`versions.tf`)을 함부로 바꾸지 마세요.** key를 잘못 바꾸면 다른 환경의 장부를 덮어쓸 수 있습니다.
